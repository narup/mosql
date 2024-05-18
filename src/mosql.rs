use crate::core;
use crate::mongo;

use case_converter::*;
use derive_more::Display;
use log::{debug, info};
use std::fs::File;
use std::io::prelude::*;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoError(String),
}

pub struct Exporter {
    namespace: String,
    sqlite_client: core::SQLiteClient,
    mongo_client: mongo::DBClient,
    export_builder: core::ExportBuilder,
}

impl Exporter {
    pub fn new(
        namespace: &str,
        export_type: &str,
        source_db_uri: &str,
        destination_db_uri: &str,
    ) -> Self {
        //source database - mongo
        let mongo_client = mongo::setup_client(source_db_uri);
        assert!(mongo_client.ping());

        info!("connected to source database {}", source_db_uri);

        info!("connected to destination database {}", destination_db_uri);

        //sqlite used for mosql specific data
        let sqlite_client = core::setup_sqlite_client("mosql");
        assert!(sqlite_client.ping());

        info!("mosql core sqlite database setup complete");

        let export_builder = core::ExportBuilder::init_new_export(namespace, export_type);
        Self {
            namespace: namespace.to_string(),
            sqlite_client,
            mongo_client,
            export_builder,
        }
    }

    pub fn generate_default_schema_mapping(&mut self) -> Result<(), MoSQLError> {
        match self.mongo_client.collections() {
            Err(err) => Err(MoSQLError::MongoError(err.to_string())),
            Ok(collections) => {
                let mut schemas = Vec::new();
                for collection in collections.iter() {
                    debug!(
                        "Generating schema mapping for collection '{}'",
                        collection.clone()
                    );
                    let schema = self.generate_schema_mapping(collection);
                    schemas.push(schema.ok().expect("error with schema"));
                }

                let _ = self
                    .export_builder
                    .set_schemas(schemas)
                    .save(&self.sqlite_client);

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

    pub fn save(&mut self) {
        let _ = self.export_builder.save(&self.sqlite_client);
    }

    fn generate_schema_mapping(&self, collection: &str) -> Result<core::Schema, MoSQLError> {
        info!("Generating schema mapping for collection {}", collection);

        match self.mongo_client.generate_collection_flat_map(collection) {
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
