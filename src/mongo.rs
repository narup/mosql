use std::collections::HashMap;
use std::error::Error;

//Mongo module to handle all the MongoDB related operations
use mongodb::{
    bson::{doc, spec::ElementType, Bson, Document},
    options::{ClientOptions, ServerApi, ServerApiVersion},
    sync::{Client, Collection, Database},
};

pub struct DBClient {
    sync_conn: Client,
    db: Database,
}

pub fn setup_client(uri: &str) -> DBClient {
    let conn = DBClient::new(uri);
    return conn;
}

impl DBClient {
    pub fn new(uri: &str) -> Self {
        let conn = match connect(uri) {
            Ok(conn) => conn,
            Err(e) => panic!("Error connecting to mongo: {}", e),
        };

        let db = conn.default_database().expect(
            "error: connection url should specify the default database name to use as a source",
        );
        Self {
            sync_conn: conn,
            db,
        }
    }

    pub fn ping(&self) -> bool {
        match self
            .sync_conn
            .database(self.db.name())
            .run_command(doc! { "ping": 1 }, None)
        {
            Ok(_) => {
                println!("Database pinged. Connected!");
                return true;
            }
            Err(e) => {
                println!("Error connecting to database:{}", e);
                return false;
            }
        }
    }

    pub fn collection<T>(&self, name: String) -> Collection<T> {
        return self.db.collection(name.as_str());
    }

    pub fn generate_collection_flat_map(
        &self,
        collection_name: String,
    ) -> Result<HashMap<String, Bson>, Box<dyn Error>> {
        let coll: Collection<Document> = self.collection(collection_name.clone());
        let result = match coll.find_one(None, None) {
            Ok(it) => it,
            Err(err) => return Err(format!("error finding the document: {}", err).into()),
        };

        let mut final_map: HashMap<String, Bson> = HashMap::new();
        if let Some(doc) = result {
            create_flat_map(&mut final_map, collection_name, &doc);
        }

        return Ok(final_map);
    }
}

fn connect(uri: &str) -> mongodb::error::Result<Client> {
    println!("Connecting to MongoDB...");
    let mut client_options = ClientOptions::parse(uri)?;

    // Set the server_api field of the client_options object to Stable API version 1
    let server_api = ServerApi::builder().version(ServerApiVersion::V1).build();
    client_options.server_api = Some(server_api);

    // Create a new client and connect to the server
    return Client::with_options(client_options);
}

//private functions ---
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

#[cfg(test)]
mod tests {
    use crate::mongo;

    use mongodb::bson::{doc, DateTime};
    use mongodb::sync::Collection;
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

    #[test]
    fn test_mongo_setup() {
        let db_client: mongo::DBClient = setup();
        let doc = build_test_document();

        let coll: Collection<TestDocument> = db_client.collection("test_collection".to_string());
        let res = coll.insert_one(doc, None).expect("insert failed ");
        assert_ne!(res.inserted_id.to_string(), "");
    }

    fn build_test_document() -> TestDocument {
        let mut attrs_value = HashMap::new();
        attrs_value.insert("key1".to_string(), "value1".to_string());
        attrs_value.insert("key2".to_string(), "value2".to_string());

        // Convert the timestamp to a BSON DateTime
        let now = DateTime::now();

        let doc = TestDocument {
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
        };

        return doc;
    }

    fn setup() -> mongo::DBClient {
        return mongo::DBClient::new("mongodb://localhost:27017/mosql");
    }
}
