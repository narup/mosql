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
                Ok(sqlite_conn) => {
                    info!("Running migration...");
                    if let Err(err) = migration::Migrator::up(&sqlite_conn, None).await {
                        panic!("Error connecting to sqlite {}", err);
                    }
                    info!("Migration ran successfully");

                    return sqlite_conn;
                }
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
    pub source_connection: Option<Connection>,
    pub dest_connection: Option<Connection>,
    pub creator: Option<User>,
    pub updator: Option<User>,
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
    pub email: String,
    pub created_at: String,
}

pub struct ExportBuilder {
    entity: Option<export::ActiveModel>,
    export: Option<Export>,
}

impl ExportBuilder {
    pub fn init_new_export(namespace: &str, export_type: &str) -> ExportBuilder {
        return ExportBuilder {
            export: Some(Export {
                id: None,
                namespace: namespace.to_string(),
                export_type: export_type.to_string(),
                exclude_filters: Vec::new(),
                include_filters: Vec::new(),
                schemas: Vec::new(),
                source_connection: None,
                dest_connection: None,
                creator: None,
                updator: None,
            }),
            entity: None,
        };
    }

    pub fn add_connection(
        &mut self,
        conn_type: &str,
        name: &str,
        connection_uri: &str,
    ) -> &mut Self {
        let conn = Connection {
            id: None,
            name: name.to_string(),
            connection_string: connection_uri.to_string(),
        };
        if conn_type == "source" {
            self.export.as_mut().unwrap().source_connection = Some(conn);
        } else {
            self.export.as_mut().unwrap().dest_connection = Some(conn);
        }

        self
    }

    pub fn include_collections(&mut self, collections: Vec<String>) -> &mut Self {
        self.export.as_mut().unwrap().include_filters = collections;
        return self;
    }

    pub fn exclude_collections(&mut self, collections: Vec<String>) -> &mut Self {
        self.export.as_mut().unwrap().exclude_filters = collections;
        return self;
    }

    pub fn set_updator_info(&mut self, user: User) -> &mut Self {
        self.export.as_mut().unwrap().updator = Some(user);
        return self;
    }

    pub fn set_creator_info(&mut self, user: User) -> &mut Self {
        self.export.as_mut().unwrap().creator = Some(user);
        return self;
    }

    pub fn set_schemas(&mut self, schemas: Vec<Schema>) -> &mut Self {
        self.export.as_mut().unwrap().schemas = schemas;
        return self;
    }

    pub fn export_entity(&self) -> Option<::entity::export::Model> {
        if self.entity.is_none() {
            debug!("Entity not populated");
            return None;
        }

        match self.entity.clone().unwrap().try_into_model() {
            Ok(model) => return Some(model),
            Err(err) => {
                println!("ERROR: {}", err);
                return None;
            }
        }
    }

    pub fn get_export(&mut self) -> &Export {
        return self.export.as_mut().unwrap();
    }

    pub fn save(&mut self, db_client: &SQLiteClient) -> Result<bool, Box<dyn Error>> {
        if self.export.is_none() {
            return Err(format!(
                "export data not populated, use ExportBuilder to build the export first"
            )
            .into());
        }

        if self.export.as_ref().unwrap().creator.is_none() {
            return Err(format!(
                "export user cannot be blank, use ExportBuilder to build the export first"
            )
            .into());
        }

        if self.export.as_ref().unwrap().source_connection.is_none() {
            return Err(format!(
                "source db connection not defined, use ExportBuilder to build the export first"
            )
            .into());
        }

        if self.export.as_ref().unwrap().dest_connection.is_none() {
            return Err(format!(
                "destination db connection not defined, use ExportBuilder to build the export first"
            )
            .into());
        }

        let export = self.export.as_mut().unwrap();

        self::check_and_delete_existing_export(db_client, export.namespace.as_str())?;

        let user_id = self::save_export_user(db_client, export)?;
        let source_conn_id = self::save_export_connection(db_client, "source", export)?;
        let dest_conn_id = self::save_export_connection(db_client, "destination", export)?;

        let mut entity = export::ActiveModel {
            namespace: Set(export.namespace.to_owned()),
            r#type: Set(export.export_type.to_owned()),
            include_filters: Set(Some(export.include_filters.join(",").to_owned())),
            exclude_filters: Set(Some(export.exclude_filters.join(",").to_owned())),
            creator_id: Set(user_id),
            updator_id: Set(user_id),
            source_connection_id: Set(source_conn_id),
            destination_connection_id: Set(dest_conn_id),
            created_at: Set(Utc::now().to_rfc3339()),
            updated_at: Set(Utc::now().to_rfc3339()),
            ..Default::default()
        };

        let export_res = task::block_on(save_export(&db_client, &entity));
        if let Err(err) = export_res {
            return Err(format!("Error saving export data: {}", err).into());
        }

        let export_id = export_res.unwrap().id;

        //update the id values on the Export struct model
        for schema in self.export.as_mut().unwrap().schemas.iter_mut() {
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

        entity.id = Set(export_id);
        self.entity = Some(entity.clone());

        return Ok(true);
    }
}

fn check_and_delete_existing_export(
    db_client: &SQLiteClient,
    namespace: &str,
) -> Result<(), Box<dyn Error>> {
    //check and delete existing export if it exists for the same namespace
    if task::block_on(check_export_exists(&db_client, namespace)) {
        match task::block_on(delete_export(&db_client, namespace)) {
            Ok(_) => info!("Deleted saved export"),
            Err(err) => {
                return Err(format!("Failed to delete export: {}", err).into());
            }
        }
    }

    Ok(())
}

fn save_export_user(db_client: &SQLiteClient, export: &mut Export) -> Result<i32, Box<dyn Error>> {
    let user = export.creator.as_ref().unwrap();
    info!("User email check {}", user.email);
    let user_id = task::block_on(user_by_email(db_client, &user.email.clone()));
    info!("User id {}", user_id);
    if user_id > 0 {
        info!("found existing user");
        return Ok(user_id);
    }

    let user_res = task::block_on(save_new_user(
        db_client,
        user.full_name.to_owned(),
        user.email.to_owned(),
    ));
    if let Err(err) = user_res {
        return Err(format!("error saving user data: {}", err).into());
    }

    let user_id = user_res.unwrap().id;
    export.creator.as_mut().unwrap().id = Some(user_id);
    export.updator.as_mut().unwrap().id = Some(user_id);

    Ok(user_id)
}

fn save_export_connection(
    db_client: &SQLiteClient,
    conn_type: &str,
    export: &mut Export,
) -> Result<i32, Box<dyn Error>> {
    let name = if conn_type == "source" {
        export.source_connection.as_mut().unwrap().name.to_owned()
    } else {
        export.dest_connection.as_mut().unwrap().name.to_owned()
    };

    let conn_string = if conn_type == "source" {
        export
            .source_connection
            .as_mut()
            .unwrap()
            .connection_string
            .to_owned()
    } else {
        export
            .dest_connection
            .as_mut()
            .unwrap()
            .connection_string
            .to_owned()
    };

    let source_conn_res = task::block_on(save_data_source_connection(db_client, name, conn_string));
    if let Err(err) = source_conn_res {
        return Err(format!("error saving source connection data: {}", err).into());
    }
    let conn_id = source_conn_res.unwrap().id;
    if conn_type == "source" {
        export.source_connection.as_mut().unwrap().id = Some(conn_id);
    } else {
        export.dest_connection.as_mut().unwrap().id = Some(conn_id);
    }

    Ok(conn_id)
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
    full_name: String,
    email: String,
) -> Result<user::Model, sea_orm::DbErr> {
    let u = user::ActiveModel {
        full_name: Set(full_name),
        email: Set(email),
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

pub async fn user_by_email(db_client: &SQLiteClient, email: &str) -> i32 {
    match user::Entity::find()
        .from_raw_sql(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            r#"SELECT * FROM user WHERE email = $1"#,
            [email.into()],
        ))
        .one(&db_client.conn)
        .await
    {
        Ok(model) => {
            if let Some(user) = model {
                info!("Found user model - {:?}", user);
                return user.id;
            } else {
                info!("No saved user found for email {}", email);
                return -1;
            }
        }
        Err(err) => {
            info!("Error checking user count - {}", err);
            return -1;
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
        Err(err) => Err(format!("{}", err).into()),
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

        let mapping_1_1 = core::Mapping {
            id: None,
            source_field_name: generate_random_string(6),
            destination_field_name: generate_random_string(8),
            source_field_type: "string".to_owned(),
            destination_field_type: "text".to_owned(),
            version: "1.0".to_string(),
        };

        let mapping_1_2 = core::Mapping {
            id: None,
            source_field_name: generate_random_string(6),
            destination_field_name: generate_random_string(8),
            source_field_type: "number".to_owned(),
            destination_field_type: "float".to_owned(),
            version: "1.0".to_string(),
        };

        let mappings_1 = vec![mapping_1_1, mapping_1_2];

        let schema_1 = core::Schema {
            id: None,
            namespace: namespace.clone(),
            collection: generate_random_string(8),
            sql_table: generate_random_string(6),
            version: "1.0".to_string(),
            indexes: Vec::new(),
            mappings: mappings_1,
        };

        let mapping_2_1 = core::Mapping {
            id: None,
            source_field_name: generate_random_string(6),
            destination_field_name: generate_random_string(8),
            source_field_type: "string".to_owned(),
            destination_field_type: "text".to_owned(),
            version: "1.0".to_string(),
        };

        let schema_2 = core::Schema {
            id: None,
            namespace: namespace.clone(),
            collection: generate_random_string(8),
            sql_table: generate_random_string(6),
            version: "1.0".to_string(),
            indexes: Vec::new(),
            mappings: vec![mapping_2_1],
        };

        let schemas = vec![schema_1, schema_2];

        let export_builder = export_builder
            .add_connection("source", "mongo", "mongo://localhost:27017/mosql")
            .add_connection(
                "destination",
                "postgres",
                "postgres://localhost:54324/postgres",
            )
            .include_collections(Vec::new())
            .exclude_collections(vec![
                "exclude_coll1".to_string(),
                "exclude_coll2".to_string(),
            ])
            .set_schemas(schemas)
            .set_creator_info(creator.clone())
            .set_updator_info(creator);

        let saved = export_builder.save(&sqlite).expect("Save failed");
        assert!(saved);

        let saved_export = export_builder
            .export_entity()
            .expect("saved export should be ok");

        assert!(saved_export.id > 0);
        assert_eq!(saved_export.namespace, namespace.clone());
        assert!(saved_export.creator_id > 0);
        assert!(saved_export.source_connection_id > 0);
        assert!(saved_export.destination_connection_id > 0);

        println!(
            "IDs - export id: {}, creator id: {}, source conn id: {}, dest conn id: {}",
            saved_export.id,
            saved_export.creator_id,
            saved_export.source_connection_id,
            saved_export.destination_connection_id
        );

        if let Err(err) = core::check_and_delete_existing_export(&sqlite, namespace.as_str()) {
            panic!("test failed: {}", err);
        } else {
            println!("deleted export {}", namespace.clone());
        }

        println!("test passed!!");
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
            email,
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

        let user = task::block_on(core::save_new_user(&sqlite, full_name.clone(), email))
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
