use std::error::Error;

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
    pub id: Option<i32>,
    pub namespace: String,
    pub export_type: String,
    pub exclude_filters: Vec<String>,
    pub include_filters: Vec<String>,
    pub schemas: Vec<Schema>,
    pub source_connection: Connection,
    pub dest_connection: Connection,
    pub creator: User,
    pub updator: User,
}

#[derive(Serialize, Deserialize)]
pub struct Schema {
    pub id: Option<i32>,
    pub namespace: String,
    pub collection: String,
    pub sql_table: String,
    pub version: String,
    pub indexes: Vec<String>,
    pub mappings: Vec<Mapping>,
}

#[derive(Serialize, Deserialize)]
pub struct Mapping {
    pub id: Option<i32>,
    pub source_field_name: String,
    pub destination_field_name: String,
    pub source_field_type: String,
    pub destination_field_type: String,
    pub version: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Connection {
    pub id: Option<i32>,
    pub name: String,
    pub connection_string: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct User {
    pub id: Option<i32>,
    pub full_name: String,
    pub user_name: String,
    pub email: Option<String>,
    pub created_at: String,
}

pub struct ExportBuilder {
    entity: export::ActiveModel,
    export: Export,
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

        let user = User {
            id: None,
            full_name: "N/A".to_string(),
            user_name: "N/A".to_string(),
            email: None,
            created_at: "N/A".to_string(),
        };

        let connection = Connection {
            id: None,
            name: "N/A".to_string(),
            connection_string: "N/A".to_string(),
        };

        let export = Export {
            id: None,
            namespace: namespace.to_string(),
            export_type: export_type.to_string(),
            exclude_filters: Vec::new(),
            include_filters: Vec::new(),
            schemas: Vec::new(),
            creator: user.clone(),
            updator: user.clone(),
            source_connection: connection.clone(),
            dest_connection: connection.clone(),
        };

        return ExportBuilder { entity, export };
    }

    pub fn add_connection(&mut self, conn_type: String, connection: Connection) -> &mut Self {
        if conn_type == "source" {
            self.export.source_connection = connection;
        } else {
            self.export.dest_connection = connection;
        }

        return self;
    }

    pub fn include_collections(&mut self, collections: Vec<String>) -> &mut Self {
        self.entity.include_filters = Set(Some(collections.join(",")));
        return self;
    }

    pub fn exclude_collections(&mut self, collections: Vec<String>) -> &mut Self {
        self.entity.exclude_filters = Set(Some(collections.join(",")));
        return self;
    }

    pub fn set_updator_info(&mut self, user: User) -> &mut Self {
        self.export.creator = user;
        return self;
    }

    pub fn set_creator_info(&mut self, user: User) -> &mut Self {
        self.export.creator = user;
        return self;
    }

    pub fn set_schemas(&mut self, schemas: Vec<Schema>) -> &mut Self {
        self.export.schemas = schemas;
        return self;
    }

    pub fn export_entity(&self) -> Option<::entity::export::Model> {
        match self.entity.clone().try_into_model() {
            Ok(model) => return Some(model),
            Err(_) => return None,
        }
    }

    pub fn get_export(&self) -> &Export {
        return &self.export;
    }

    pub fn save(&mut self, db_client: &SQLiteClient) -> Result<bool, Box<dyn Error>> {
        if task::block_on(check_export_exists(
            &db_client,
            self.export.namespace.as_str(),
        )) {
            //delete export
            match task::block_on(delete_export(&db_client, self.export.namespace.as_str())) {
                Ok(_) => info!("Deleted saved export"),
                Err(err) => info!("Deleting existing export failed-{}", err),
            }
        }

        let user_res = task::block_on(save_new_user(
            db_client,
            self.export.creator.user_name.to_owned(),
            self.export.creator.full_name.to_owned(),
            self.export
                .creator
                .email
                .to_owned()
                .unwrap_or("default@mosql".to_string()),
        ));
        if let Err(err) = user_res {
            return Err(format!("error saving user data: {}", err).into());
        }

        let user_id = user_res.unwrap().id;
        self.export.creator.id = Some(user_id);
        self.export.updator.id = Some(user_id);

        let source_conn_res = task::block_on(save_data_source_connection(
            db_client,
            self.export.source_connection.name.to_owned(),
            self.export.source_connection.connection_string.to_owned(),
        ));
        if let Err(err) = source_conn_res {
            return Err(format!("error saving source connection data: {}", err).into());
        }
        let source_conn_id = source_conn_res.unwrap().id;
        self.export.source_connection.id = Some(source_conn_id);

        let dest_conn_res = task::block_on(save_data_source_connection(
            db_client,
            self.export.dest_connection.name.to_owned(),
            self.export.dest_connection.connection_string.to_owned(),
        ));
        if let Err(err) = dest_conn_res {
            return Err(format!("error saving source connection data: {}", err).into());
        }
        let dest_conn_id = dest_conn_res.unwrap().id;
        self.export.dest_connection.id = Some(dest_conn_id);

        let entity = export::ActiveModel {
            namespace: Set(self.export.namespace.to_owned()),
            r#type: Set(self.export.export_type.to_owned()),
            include_filters: Set(Some(self.export.include_filters.join(",").to_owned())),
            exclude_filters: Set(Some(self.export.exclude_filters.join(",").to_owned())),
            creator_id: Set(user_id),
            updator_id: Set(user_id),
            created_at: Set(Utc::now().to_rfc3339()),
            updated_at: Set(Utc::now().to_rfc3339()),
            ..Default::default()
        };

        let export_res = task::block_on(save_export(&db_client, &self.entity));
        if let Err(err) = export_res {
            return Err(format!("Error saving export data: {}", err).into());
        }

        let export_id = export_res.unwrap().id;

        for schema in self.export.schemas.iter_mut() {
            let schema_entity = ::entity::schema::ActiveModel {
                namespace: Set(schema.namespace.to_owned()),
                collection: Set(schema.collection.to_owned()),
                sql_table: Set(schema.sql_table.to_owned()),
                version: Set(schema.version.to_owned()),
                export_id: Set(export_id),
                indexes: Set(Some("".to_string())),
                ..Default::default()
            };

            let schema_res = task::block_on(schema_entity.insert(&db_client.conn));
            if let Err(err) = schema_res {
                return Err(format!(
                    "Error saving schema data: {} for collection {}",
                    err, schema.collection
                )
                .into());
            }
            let schema_id = schema_res.unwrap().id;
            schema.id = Some(schema_id);

            for mapping in schema.mappings.iter_mut() {
                let mapping_entity = mapping::ActiveModel {
                    schema_id: Set(schema_id),
                    source_field_name: Set(mapping.source_field_name.to_owned()),
                    destination_field_name: Set(mapping.destination_field_name.to_owned()),
                    source_field_type: Set(mapping.source_field_type.to_owned()),
                    destination_field_type: Set(mapping.destination_field_type.to_owned()),
                    version: Set(mapping.version.to_owned()),
                    ..Default::default()
                };
                let mapping_res = task::block_on(mapping_entity.insert(&db_client.conn));
                if let Err(err) = mapping_res {
                    return Err(format!(
                        "Error saving schema data: {} for collection {}. Mapping entry failed",
                        err, schema.collection
                    )
                    .into());
                }
                let mapping_id = mapping_res.unwrap().id;
                mapping.id = Some(mapping_id);
            }
        }

        self.entity = entity.clone();

        return Ok(true);
    }
}

pub async fn save_export(
    db_client: &SQLiteClient,
    new_export: &export::ActiveModel,
) -> Result<export::Model, DbErr> {
    return new_export.clone().insert(&db_client.conn).await;
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

pub async fn check_export_exists(db_client: &SQLiteClient, namespace: &str) -> bool {
    match export::Entity::find()
        .from_raw_sql(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            r#"SELECT * FROM export WHERE namespace = $1"#,
            [namespace.into()],
        ))
        .one(&db_client.conn)
        .await
    {
        Ok(model) => {
            if let Some(export) = model {
                debug!("Found export model - {:?}", export);
                return true;
            } else {
                debug!("No saved export found for namespace {}", namespace);
                return false;
            }
        }
        Err(err) => {
            debug!("Error checking export count - {}", err);
            return false;
        }
    }
}

pub async fn delete_export(
    db_client: &SQLiteClient,
    namespace: &str,
) -> Result<bool, Box<dyn Error>> {
    match export::Entity::delete_many()
        .filter(export::Column::Namespace.eq(namespace.to_owned()))
        .exec(&db_client.conn)
        .await
    {
        Ok(delete_result) => {
            assert_eq!(delete_result.rows_affected, 1);
            Ok(true)
        }
        Err(err) => Err(format!("Errordeleting export {}", err).into()),
    }
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

        assert!(user.id > 0);
        assert!(data_source_conn_src.id > 0);
        assert!(data_source_conn_dest.id > 0);

        let namespace = generate_random_string(6);
        let mut export_builder =
            core::ExportBuilder::init_new_export(namespace.as_str(), "mongo_to_postgres");

        let creator = generate_test_user();

        let export_builder = export_builder
            .add_connection(
                "source".to_string(),
                core::Connection {
                    id: None,
                    name: "mongo".to_string(),
                    connection_string: "mongo://localhost:27017/mosql".to_string(),
                },
            )
            .add_connection(
                "destination".to_string(),
                core::Connection {
                    id: None,
                    name: "postgres".to_string(),
                    connection_string: "postgres://localhost:54324/postgres".to_string(),
                },
            )
            .include_collections(Vec::new())
            .exclude_collections(vec![
                "exclude_coll1".to_string(),
                "exclude_coll2".to_string(),
            ])
            .set_schemas(Vec::new())
            .set_creator_info(creator);

        let saved = export_builder.save(&sqlite).expect("Save failed");
        assert!(saved);

        let saved_export = export_builder
            .export_entity()
            .expect("saved export should be ok");

        assert!(saved_export.id > 0);
        assert_eq!(saved_export.namespace, namespace.clone());
        assert_eq!(saved_export.creator_id, user.id);
        assert_eq!(saved_export.source_connection_id, data_source_conn_src.id);
        assert_eq!(
            saved_export.destination_connection_id,
            data_source_conn_dest.id
        );
    }

    fn generate_test_user() -> core::User {
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

        return core::User {
            id: None,
            full_name,
            user_name: generate_random_string(6),
            email: Some(email),
            created_at: "date".to_string(),
        };
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
