use crate::core;
use crate::mongo;

use async_std::task;
use derive_more::Display;

#[derive(Debug, Display)]
pub enum MoSQLError {
    MongoError(String),
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

    pub fn generate_schema_mapping(&self, collection: String) -> Result<(), MoSQLError> {
        println!("Generating schema mapping...");

        match self.mongo_client.generate_collection_flat_map(collection) {
            Ok(flat_map) => {
                for (key, value) in flat_map.iter() {
                    println!("{}===>{:?}", key, value);
                }
            }
            Err(err) => return Err(MoSQLError::MongoError(err.to_string())),
        };

        Ok(())
    }

    pub fn save(&self) {
        let _ = task::block_on(self.export_builder.save(&self.sqlite_client));
    }
}

// ----- all the private utility functions below
