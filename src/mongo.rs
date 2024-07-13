//Mongo module to handle all the MongoDB related operations
use log::{debug, info};
use mongodb::{
    bson::{doc, spec::ElementType, Bson, Document},
    Client, Collection, Database,
};

use std::collections::HashMap;
use std::error::Error;

#[derive(Debug)]
pub struct DocumentValue {
    pub value: Bson,
    pub value_type: ElementType,
}

impl DocumentValue {
    pub fn sql_type(&self) -> String {
        let sql_val_type = match self.value_type {
            ElementType::String | ElementType::ObjectId | ElementType::Null => "text",
            ElementType::Double | ElementType::Decimal128 => "numeric",
            ElementType::Int32 => "integer",
            ElementType::Int64 => "bigint",
            ElementType::Boolean => "boolean",
            ElementType::Timestamp | ElementType::DateTime => "timestamp with time zone",
            _ => "text",
        };

        sql_val_type.to_string()
    }

    pub fn mongo_type(&self) -> String {
        let mtype = match self.value_type {
            ElementType::EmbeddedDocument => "embed",
            ElementType::Double => "double",
            ElementType::String => "string",
            ElementType::Array => "array",
            ElementType::Binary => "binary",
            ElementType::Undefined => "undefined",
            ElementType::ObjectId => "object_id",
            ElementType::Boolean => "boolean",
            ElementType::DateTime => "datetime",
            ElementType::Null => "null",
            ElementType::RegularExpression => "regular_expression",
            ElementType::DbPointer => "db_pointer",
            ElementType::JavaScriptCode => "javascript_code",
            ElementType::Symbol => "symbol",
            ElementType::JavaScriptCodeWithScope => "javascript_code_with_scope",
            ElementType::Int32 => "int32",
            ElementType::Timestamp => "timestamp",
            ElementType::Int64 => "int64",
            ElementType::Decimal128 => "decimal128",
            ElementType::MaxKey => "max_key",
            ElementType::MinKey => "min_key",
        };
        mtype.to_string()
    }
}

pub struct DBClient {
    conn: Client,
    db: Database,
}

pub async fn setup_client(uri: &str) -> DBClient {
    DBClient::new(uri).await
}

impl DBClient {
    pub async fn new(uri: &str) -> Self {
        let conn = match Client::with_uri_str(uri).await {
            Ok(conn) => conn,
            Err(e) => panic!("Error connecting to mongo: {}, uri: {}", e, uri),
        };

        let db = conn.default_database().expect(
            "error: connection url should specify the default database name to use as a source",
        );
        info!("Default database name:{}", db.name());
        Self { conn, db }
    }

    pub async fn ping(&self) -> bool {
        match self
            .conn
            .database(self.db.name())
            .run_command(doc! { "ping": 1 }, None)
            .await
        {
            Ok(_) => {
                info!("Database pinged. Connected!");
                true
            }
            Err(e) => {
                info!("Error connecting to database:{}", e);
                false
            }
        }
    }

    pub async fn collections(&self) -> Result<Vec<String>, Box<dyn Error>> {
        match self.db.list_collection_names(None).await {
            Ok(list) => Ok(list),
            Err(err) => Err(format!("error listing collection names: {}", err).into()),
        }
    }

    pub fn collection<T>(&self, name: &str) -> Collection<T> {
        self.db.collection(name)
    }

    pub async fn generate_collection_flat_map(
        &self,
        collection_name: &str,
    ) -> Result<HashMap<String, DocumentValue>, Box<dyn Error>> {
        let coll: Collection<Document> = self.collection(collection_name);
        let result = match coll.find_one(None, None).await {
            Ok(it) => it,
            Err(err) => return Err(format!("error finding the document: {}", err).into()),
        };

        let mut final_map: HashMap<String, DocumentValue> = HashMap::new();
        if let Some(doc) = result {
            create_flat_map(&mut final_map, collection_name, &doc);
        }

        Ok(final_map)
    }
}

//private functions ---
fn create_flat_map(flat_map: &mut HashMap<String, DocumentValue>, prefix: &str, doc: &Document) {
    for key in doc.keys() {
        if let Some(val) = doc.get(key) {
            let new_key = format!("{}.{}", prefix, key.as_str());
            match val.element_type() {
                ElementType::EmbeddedDocument => {
                    debug!("embedded document found, create nested keys");
                    if let Some(embeded_doc) = val.as_document() {
                        create_flat_map(flat_map, &new_key, embeded_doc)
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
                    let field_value = DocumentValue {
                        value: val.to_owned(),
                        value_type: val.element_type(),
                    };
                    flat_map.insert(new_key, field_value);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::mongo;

    use mongodb::bson::{doc, DateTime};
    use mongodb::Collection;
    use std::collections::HashMap;

    use serde::{Deserialize, Serialize};

    #[derive(Debug, Serialize, Deserialize)]
    struct TestDocument {
        name: String,
        email: String,
        city: String,
        phone_number: String,
        is_active: bool,
        int_value: i32,
        long_int_value: i64,
        decimal_value: f64,
        tags: Vec<String>,
        attrs: HashMap<String, String>,
        created_date: DateTime,
        company: Company,
    }

    #[derive(Serialize, Deserialize, Debug)]
    struct Company {
        #[serde(rename = "name")]
        name: String,
        #[serde(rename = "website_url")]
        website: String,
        #[serde(rename = "company_address")]
        address: Address,
    }

    #[derive(Serialize, Deserialize, Debug)]
    struct Address {
        #[serde(rename = "street1")]
        street: String,
        #[serde(rename = "zip_code")]
        zipcode: String,
        state: String,
        residence: bool,
    }

    #[tokio::test]
    async fn test_mongo_setup() {
        let db_client: mongo::DBClient = setup().await;
        let doc = build_test_document();

        let coll: Collection<TestDocument> = db_client.collection("test_collection");
        let res = coll.insert_one(doc, None).await.expect("insert failed ");
        assert_ne!(res.inserted_id.to_string(), "");
    }

    fn build_test_document() -> TestDocument {
        let mut attrs_value = HashMap::new();
        attrs_value.insert("key1".to_string(), "value1".to_string());
        attrs_value.insert("key2".to_string(), "value2".to_string());

        // Convert the timestamp to a BSON DateTime
        let now = DateTime::now();

        TestDocument {
            name: "John Doe".to_string(),
            email: "john.doe@mosql.io".to_string(),
            city: "San Francisco".to_string(),
            phone_number: "1112221111".to_string(),
            is_active: true,
            int_value: 21,
            long_int_value: 20000000,
            decimal_value: 304.135,
            tags: vec![
                "tag_a".to_string(),
                "tag_b".to_string(),
                "tag_c".to_string(),
            ],
            attrs: attrs_value,
            created_date: now,
            company: Company {
                name: "MoSQL, Inc".to_string(),
                website: "https://mosql.io".to_string(),
                address: Address {
                    street: "123 Mosql lane".to_string(),
                    zipcode: "94111".to_string(),
                    state: "CA".to_string(),
                    residence: false,
                },
            },
        }
    }

    async fn setup() -> mongo::DBClient {
        mongo::DBClient::new("mongodb://localhost:27017/mosql").await
    }
}
