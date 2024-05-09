use sea_orm::DatabaseConnection;

use async_std::task;
use migration::{Migrator, MigratorTrait};

use ::entity::*;
use chrono::Utc;
use sea_orm::*;

pub struct SQLiteClient {
    pub conn: DatabaseConnection,
}

pub fn setup_sqlite_client() -> SQLiteClient {
    SQLiteClient::new()
}

impl SQLiteClient {
    pub fn new() -> Self {
        let sqlite_conn = task::block_on(async {
            let database_url = "sqlite://data.db?mode=rwc";
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

pub struct ExportBuilder {
    entity: export::ActiveModel,
}

impl ExportBuilder {
    pub fn init_new_export(namespace: String, export_type: String) -> ExportBuilder {
        let entity = export::ActiveModel {
            namespace: Set(namespace),
            r#type: Set(export_type),
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
        connection: connection::Model,
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

    pub fn set_update_info(&mut self, updator: user::Model) -> &mut ExportBuilder {
        self.entity.updator_id = Set(updator.id);
        self.entity.updated_at = Set(Utc::now().to_rfc3339());

        return self;
    }

    pub async fn save(&self, db_client: &SQLiteClient) -> Result<export::Model, DbErr> {
        return self.entity.clone().insert(&db_client.conn).await;
    }
}

pub async fn save_data_source_connection(
    db_client: SQLiteClient,
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
    db_client: SQLiteClient,
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

    #[test]
    fn test_core_save_user() {
        let sqlite = core::setup_sqlite_client();
        let user = task::block_on(core::save_new_user(
            sqlite,
            "mosql".to_string(),
            "MoSQL Admin".to_string(),
            "admin@mosql.io".to_string(),
        ))
        .expect("Error creating user");

        assert_eq!(user.full_name, "MoSQL Admin");
        assert!(user.id > 0);
    }
}
