use crate::core;
use crate::mongo;

use derive_more::Display;
use mongodb::{
    bson::{spec::ElementType, Bson, Document},
    sync::Collection,
};

use async_std::task;
use std::collections::HashMap;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoConnectionError(String),
    MongoQueryError(String),
}

pub struct Exporter {
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

        println!("connected to source database {}", source_db_uri);

        println!("connected to destination database {}", destination_db_uri);

        //sqlite used for mosql specific data
        let sqlite_client = core::setup_sqlite_client("mosql");
        assert!(sqlite_client.ping());

        println!("mosql core sqlite database setup complete");

        let export_builder = core::ExportBuilder::init_new_export(namespace, export_type);
        Self {
            sqlite_client,
            mongo_client,
            export_builder,
        }
    }

    pub fn generate_schema_mapping(&self, collection: &str) -> Result<(), MoSQLError> {
        println!("Generating schema mapping...");

        let coll: Collection<Document> = self.mongo_client.collection(collection);
        let result = match coll.find_one(None, None) {
            Ok(it) => it,
            Err(err) => {
                return Err(MoSQLError::MongoQueryError(format!(
                    "error finding the document: {}",
                    err
                )))
            }
        };

        let mut final_map: HashMap<String, Bson> = HashMap::new();
        if let Some(doc) = result {
            create_flat_map(&mut final_map, collection.to_string(), &doc);
        }

        for (key, value) in final_map.iter() {
            println!("{}===>{:?}", key, value);
        }

        Ok(())
    }

    pub fn save(&self) {
        let _ = task::block_on(self.export_builder.save(&self.sqlite_client));
    }
}

// ----- all the private utility functions below

fn create_flat_map(flat_map: &mut HashMap<String, Bson>, prefix: String, doc: &Document) {
    for key in doc.keys() {
        if let Some(val) = doc.get(key) {
            let new_key = format!("{}.{}", prefix, key.to_string());

            match val.element_type() {
                ElementType::EmbeddedDocument => {
                    println!("embedded document found, create nested keys");
                    if let Some(embeded_doc) = val.as_document() {
                        create_flat_map(flat_map, new_key, embeded_doc)
                    }
                }
                ElementType::Double
                | ElementType::String
                | ElementType::Array
                | ElementType::Binary
                | ElementType::Undefined
                | ElementType::ObjectId
                | ElementType::Boolean
                | ElementType::DateTime
                | ElementType::Null
                | ElementType::RegularExpression
                | ElementType::DbPointer
                | ElementType::JavaScriptCode
                | ElementType::Symbol
                | ElementType::JavaScriptCodeWithScope
                | ElementType::Int32
                | ElementType::Timestamp
                | ElementType::Int64
                | ElementType::Decimal128
                | ElementType::MaxKey
                | ElementType::MinKey => {
                    flat_map.insert(new_key, val.to_owned());
                }
            }
        }
    }
}
