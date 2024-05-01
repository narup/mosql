use crate::mongo::Connection;
use derive_more::Display;
use mongodb::{
    bson::{spec::ElementType, Bson, Document},
    sync::Collection,
};
use std::collections::HashMap;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoConnectionError(String),
    MongoQueryError(String),
}

pub fn setup(uri: &str, db_name: &str) -> Connection {
    let conn = Connection::new(uri, db_name);
    return conn;
}

pub fn new_export() {
    println!("new export")
}

pub fn generate_schema_mapping(conn: Connection, collection: &str) -> Result<(), MoSQLError> {
    println!("Generating schema mapping...");

    let coll: Collection<Document> = conn.collection(collection);

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
