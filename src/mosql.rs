use crate::core;
use crate::mongo;
use crate::sql;
use case_converter::*;
use chrono::Utc;
use derive_more::Display;
use log::{debug, info};
use std::fs::File;
use std::io::prelude::*;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoError(String),
    PostgresError(String),
    PersistenceError(String),
}

pub struct Exporter {
    namespace: String,
    sqlite_client: core::SQLiteClient,
    postgres_client: Option<sql::PostgresClient>,
    mongo_client: Option<mongo::DBClient>,
    export_builder: core::ExportBuilder,
}

impl Exporter {
    pub async fn new(namespace: &str) -> Self {
        //sqlite used for mosql specific data
        let sqlite_client = core::setup_sqlite_client("mosql").await;
        assert!(sqlite_client.ping().await);

        info!("mosql core sqlite database setup complete");

        let export_builder = core::ExportBuilder::init_new_export(namespace, "mongo_to_postgres");
        Self {
            namespace: namespace.to_string(),
            sqlite_client,
            postgres_client: None,
            mongo_client: None,
            export_builder,
        }
    }

    pub async fn connect_source_db(&mut self) -> Result<(), MoSQLError> {
        //source database - mongo
        if let Some(connection) = &self.export_builder.get_export().source_connection {
            let conn_uri = connection.connection_string.as_str();
            let mongo_client = mongo::setup_client(conn_uri).await;
            assert!(mongo_client.ping().await);

            info!("connected to source database {}", conn_uri);

            self.mongo_client = Some(mongo_client);
            Ok(())
        } else {
            Err(MoSQLError::MongoError(
                "Source database connection info not found".to_owned(),
            ))
        }
    }

    pub async fn connect_destination_db(&mut self) -> Result<(), MoSQLError> {
        //source database - mongo
        if let Some(connection) = &self.export_builder.get_export().destination_connection {
            let conn_uri = connection.connection_string.as_str();
            let postgres_client = sql::setup_postgres_client(conn_uri).await;
            assert!(postgres_client.ping().await);

            info!("connected to destination database {}", conn_uri);
            self.postgres_client = Some(postgres_client);

            Ok(())
        } else {
            Err(MoSQLError::PostgresError(
                "Destination database connection info not found".to_owned(),
            ))
        }
    }

    pub fn set_source_db(&mut self, name: &str, connection_string: &str) {
        self.export_builder
            .add_connection("source", name, connection_string);
    }

    pub fn set_destination_db(&mut self, name: &str, connection_string: &str) {
        self.export_builder
            .add_connection("destination", name, connection_string);
    }

    pub fn exclude_collections(&mut self, collections: Vec<String>) {
        self.export_builder.exclude_collections(collections);
    }

    pub fn include_collections(&mut self, collections: Vec<String>) {
        self.export_builder.include_collections(collections);
    }

    pub fn set_creator(&mut self, email: &str, full_name: &str) {
        let user = core::User {
            id: None,
            email: email.to_string(),
            full_name: full_name.to_string(),
            created_at: Utc::now().to_rfc3339(),
        };
        self.export_builder.set_creator_info(user.clone());
        self.export_builder.set_updator_info(user);
    }

    pub async fn generate_default_schema_mapping(&mut self) -> Result<(), MoSQLError> {
        if self.mongo_client.is_none() {
            self.connect_source_db().await?;
        }

        match self.mongo_client.as_ref().unwrap().collections().await {
            Err(err) => Err(MoSQLError::MongoError(err.to_string())),
            Ok(collections) => {
                let mut schemas = Vec::new();
                for collection in collections.iter() {
                    info!(
                        "Generating schema mapping for collection '{}'",
                        collection.clone()
                    );
                    let schema = self.generate_schema_mapping(collection).await;
                    schemas.push(schema.ok().expect("error with schema"));
                }

                match self
                    .export_builder
                    .set_schemas(schemas)
                    .save(&self.sqlite_client)
                    .await
                {
                    Err(err) => panic!("Error saving: {}", err),
                    Ok(_) => info!("Export saved"),
                }

                let json_data =
                    serde_json::to_string_pretty(&self.export_builder.get_export()).unwrap();

                // Write the JSON data to a file
                let file_name = format!("{}_schema.json", "namespace");
                let mut file = File::create(file_name).expect("Failed to create file");
                file.write_all(json_data.as_bytes())
                    .expect("Failed to write to file");

                Ok(())
            }
        }
    }

    pub async fn save(&mut self) -> Result<core::Export, MoSQLError> {
        match self.export_builder.save(&self.sqlite_client).await {
            Err(err) => {
                Err(MoSQLError::PersistenceError(format!("Save failed. Error: {}", err)).into())
            }
            Ok(saved) => {
                if saved {
                    let saved_export = self.export_builder.get_export();
                    Ok(saved_export)
                } else {
                    Err(MoSQLError::PersistenceError(
                        "Save failed. Unknown error".to_string(),
                    ))
                }
            }
        }
    }

    pub async fn start_full_export(self) {
        self.postgres_client.unwrap().ping().await;
    }

    async fn generate_schema_mapping(
        &mut self,
        collection: &str,
    ) -> Result<core::Schema, MoSQLError> {
        info!("Generating schema mapping for collection {}", collection);

        match self
            .mongo_client
            .as_ref()
            .unwrap()
            .generate_collection_flat_map(collection)
            .await
        {
            Ok(flat_map) => {
                let mut mappings = Vec::new();

                for (key, value) in flat_map.iter() {
                    debug!("{}===>{:?}", key, value);

                    //collection key has a collection name as a prefix, remove that for the sql
                    //table name. for instance "my_collection.fieldName" becomes "field_name"
                    let prefix_len = collection.len();
                    let sql_field_name = &key[(prefix_len + 1)..];
                    let sql_field_name = camel_to_snake(&sql_field_name.replace(".", "_"));

                    let mapping = core::Mapping {
                        id: None,
                        source_field_name: key.to_string(),
                        destination_field_name: sql_field_name.to_string(),
                        source_field_type: value.mongo_type(),
                        destination_field_type: value.sql_type(),
                        version: "1.0".to_string(),
                    };
                    mappings.push(mapping);
                }

                let schema = core::Schema {
                    id: None,
                    namespace: self.namespace.clone(),
                    collection: collection.to_string(),
                    sql_table: camel_to_snake(collection),
                    version: "1.0".to_string(),
                    indexes: Vec::new(),
                    mappings,
                };

                return Ok(schema);
            }
            Err(err) => return Err(MoSQLError::MongoError(err.to_string())),
        };
    }
}

// ----- all the private utility functions below
