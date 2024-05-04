//Mongo module to handle all the MongoDB related operations
use mongodb::{
    bson::doc,
    error::Result,
    options::{ClientOptions, ServerApi, ServerApiVersion},
    sync::{Client, Collection, Database},
};

pub struct Connection {
    sync_client: Client,
    db: Database,
}

pub fn setup_connection(uri: &str, db_name: &str) -> Connection {
    let conn = Connection::new(uri, db_name);
    return conn;
}

impl Connection {
    pub fn new(uri: &str, db_name: &str) -> Self {
        let client = match connect(uri) {
            Ok(client) => client,
            Err(e) => panic!("Error connecting to mongo: {}", e),
        };

        let db = client.database(db_name);
        Self {
            sync_client: client,
            db,
        }
    }

    pub fn ping(&self) -> bool {
        match self
            .sync_client
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

    pub fn collection<T>(&self, name: &str) -> Collection<T> {
        return self.db.collection(name);
    }
}

fn connect(uri: &str) -> Result<Client> {
    println!("Connecting to MongoDB...");
    let mut client_options = ClientOptions::parse(uri)?;

    // Set the server_api field of the client_options object to Stable API version 1
    let server_api = ServerApi::builder().version(ServerApiVersion::V1).build();
    client_options.server_api = Some(server_api);

    // Create a new client and connect to the server
    return Client::with_options(client_options);
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
        let conn: mongo::Connection = setup();
        let doc = build_test_document();

        let coll: Collection<TestDocument> = conn.collection("test_collection");
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

    fn setup() -> mongo::Connection {
        return mongo::Connection::new("mongodb://localhost:27017", "mosql");
    }
}
