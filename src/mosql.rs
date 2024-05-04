use crate::core;
use crate::mongo;

use ::entity::export;
use chrono::Utc;
use derive_more::Display;
use mongodb::{
    bson::{spec::ElementType, Bson, Document},
    sync::Collection,
};
use sea_orm::*;
use std::collections::HashMap;

use ::entity::prelude::*;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoConnectionError(String),
    MongoQueryError(String),
}

pub async fn new_export(conn: core::Connection) {
    println!("new export");

    let exports: Vec<export::Model> = Export::find()
        .all(&conn.conn)
        .await
        .expect("should not be empty");

    assert_eq!(exports.len(), 1);

    let new_export = export::ActiveModel {
        namespace: Set("mosql".to_string()),
        r#type: Set("mongo_to_postgres".to_string()),
        created_at: Set(Utc::now().to_rfc3339()),
        updated_at: Set(Utc::now().to_rfc3339()),
        source_connection_id: Set(1),
        destination_connection_id: Set(1),
        exclude_filters: Set(Some("".to_string())),
        include_filters: Set(Some("".to_string())),
        creator_id: Set(1),
        updator_id: Set(1),
        ..Default::default()
    };
    println!("new export {:?}", new_export);
}

pub fn generate_schema_mapping(
    conn: mongo::Connection,
    collection: &str,
) -> Result<(), MoSQLError> {
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
