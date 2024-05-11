use sea_orm::DatabaseConnection;

use async_std::task;
use migration::{Migrator, MigratorTrait};

use ::entity::*;
use chrono::Utc;
use log::{debug, info};
use sea_orm::*;
use serde::{Deserialize, Serialize};

pub struct SQLiteClient {
    pub conn: DatabaseConnection,
}

pub fn setup_sqlite_client(name: &str) -> SQLiteClient {
    SQLiteClient::new(name)
}

impl SQLiteClient {
    pub fn new(name: &str) -> Self {
        info!("Setting up sqlite database");

        let sqlite_conn = task::block_on(async {
            let database_url = format!("sqlite://{}_db.db?mode=rwc", name);
            debug!("sqlite database url {}", database_url);

            match setup_sqlite_connection(&database_url).await {
                Ok(sqlite_conn) => return sqlite_conn,
                Err(err) => panic!("Error connecting to sqlite {}", err),
            }
        });

        Self { conn: sqlite_conn }
    }

    pub fn ping(&self) -> bool {
        let res = task::block_on(async {
            match self.conn.ping().await {
                Ok(_) => return true,
                Err(_) => return false,
            }
        });

        return res;
    }
}

//-- export models for data transfers
//
#[derive(Serialize, Deserialize)]
pub struct Export {
    pub namespace: String,
    pub export_type: String,
    pub exclude_filters: Vec<String>,
    pub include_filters: Vec<String>,
    pub schemas: Vec<Schema>,
}

#[derive(Serialize, Deserialize)]
pub struct Schema {
    pub namespace: String,
    pub collection: String,
    pub sql_table: String,
    pub version: String,
    pub indexes: Vec<String>,
    pub mappings: Vec<Mapping>,
}

#[derive(Serialize, Deserialize)]
pub struct Mapping {
    pub source_field_name: String,
    pub destination_field_name: String,
    pub source_field_type: String,
    pub destination_field_type: String,
    pub version: String,
}

pub struct ExportBuilder {
    entity: export::ActiveModel,
}

impl ExportBuilder {
    pub fn init_new_export(namespace: &str, export_type: &str) -> ExportBuilder {
        let entity = export::ActiveModel {
            namespace: Set(namespace.to_string()),
            r#type: Set(export_type.to_string()),
            creator_id: Set(999999),
            updator_id: Set(999999),
            created_at: Set(Utc::now().to_rfc3339()),
            updated_at: Set(Utc::now().to_rfc3339()),
            ..Default::default()
        };

        return ExportBuilder { entity };
    }

    pub fn add_connection(
        &mut self,
        conn_type: String,
        connection: &connection::Model,
    ) -> &mut ExportBuilder {
        if conn_type == "source" {
            self.entity.source_connection_id = Set(connection.id);
        } else {
            self.entity.destination_connection_id = Set(connection.id);
        }

        return self;
    }

    pub fn include_collections(&mut self, collections: Vec<String>) -> &mut ExportBuilder {
        self.entity.include_filters = Set(Some(collections.join(",")));
        return self;
    }

    pub fn exclude_collections(&mut self, collections: Vec<String>) -> &mut ExportBuilder {
        self.entity.exclude_filters = Set(Some(collections.join(",")));
        return self;
    }

    pub fn set_update_info(&mut self, updator: &user::Model) -> &mut ExportBuilder {
        self.entity.updator_id = Set(updator.id);
        self.entity.updated_at = Set(Utc::now().to_rfc3339());

        return self;
    }

    pub fn set_creator_info(&mut self, creator: &user::Model) -> &mut ExportBuilder {
        self.entity.creator_id = Set(creator.id);
        self.entity.created_at = Set(Utc::now().to_rfc3339());

        self.entity.updator_id = Set(creator.id);
        self.entity.updated_at = Set(Utc::now().to_rfc3339());

        return self;
    }

    pub async fn save(&self, db_client: &SQLiteClient) -> Result<export::Model, DbErr> {
        return self.entity.clone().insert(&db_client.conn).await;
    }
}

pub async fn save_data_source_connection(
    db_client: &SQLiteClient,
    name: String,
    connection_string: String,
) -> Result<connection::Model, sea_orm::DbErr> {
    let c = connection::ActiveModel {
        name: Set(name),
        connection_string: Set(connection_string),
        ..Default::default()
    };

    return c.insert(&db_client.conn).await;
}

pub async fn save_new_user(
    db_client: &SQLiteClient,
    user_name: String,
    full_name: String,
    email: String,
) -> Result<user::Model, sea_orm::DbErr> {
    let u = user::ActiveModel {
        user_name: Set(user_name),
        full_name: Set(full_name),
        email: Set(Some(email)),
        created_at: Set(Utc::now().to_rfc3339()),
        ..Default::default()
    };

    return u.insert(&db_client.conn).await;
}

async fn setup_sqlite_connection(database_url: &str) -> Result<DatabaseConnection, sea_orm::DbErr> {
    let connection = sea_orm::Database::connect(database_url).await?;
    Migrator::up(&connection, None).await?;

    return Ok(connection);
}

#[cfg(test)]
mod tests {
    use crate::core;
    use async_std::task;
    use entity::*;
    use rand::{distributions::Alphanumeric, Rng};

    use super::SQLiteClient;

    #[test]
    fn test_sqlite_crud_operation() {
        let sqlite = core::setup_sqlite_client("mosql_test");
        let user = test_core_save_user(&sqlite);
        let data_source_conn_src = test_core_save_data_source_connection(&sqlite);
        let data_source_conn_dest = test_core_save_data_source_connection(&sqlite);

        let namespace = generate_random_string(6);
        let export_builder =
            &mut core::ExportBuilder::init_new_export(namespace.as_str(), "mongo_to_postgres");

        let export_builder = export_builder
            .add_connection("source".to_string(), &data_source_conn_src)
            .add_connection("destination".to_string(), &data_source_conn_dest)
            .include_collections(Vec::new())
            .exclude_collections(vec![
                "exclude_coll1".to_string(),
                "exclude_coll2".to_string(),
            ])
            .set_creator_info(&user);

        //save
        let saved_export =
            task::block_on(export_builder.save(&sqlite)).expect("failed to save an export details");

        assert!(saved_export.id > 0);
        assert_eq!(saved_export.namespace, namespace.clone());
        assert_eq!(saved_export.creator_id, user.id);
        assert_eq!(saved_export.source_connection_id, data_source_conn_src.id);
        assert_eq!(
            saved_export.destination_connection_id,
            data_source_conn_dest.id
        );
    }

    fn test_core_save_user(sqlite: &core::SQLiteClient) -> user::Model {
        let full_name = format!(
            "{} {}",
            generate_random_string(6),
            generate_random_string(7)
        );
        let email = format!(
            "{}@{}.com",
            generate_random_string(6),
            generate_random_string(5)
        );

        let user = task::block_on(core::save_new_user(
            &sqlite,
            generate_random_string(6),
            full_name.clone(),
            email,
        ))
        .expect("Error creating user");

        assert_eq!(user.full_name, full_name);
        assert!(user.id > 0);

        return user;
    }

    fn test_core_save_data_source_connection(sqlite: &SQLiteClient) -> connection::Model {
        let name = format!("mongo_{}", generate_random_string(5));
        let data_source_conn = task::block_on(core::save_data_source_connection(
            &sqlite,
            name.clone(),
            "mongo://localhost:27017".to_string(),
        ))
        .expect("Error creating data source connection");

        assert_eq!(data_source_conn.name, name);
        assert!(data_source_conn.id > 0);

        return data_source_conn;
    }

    fn generate_random_string(length: usize) -> String {
        let rng = rand::thread_rng();
        let random_string: String = rng
            .sample_iter(&Alphanumeric)
            .take(length)
            .map(char::from)
            .collect();
        random_string
    }
}
