mod core;
mod export;
mod mongo;

use async_std::task;
use migration::{Migrator, MigratorTrait};
use sea_orm::DatabaseConnection;

fn main() {
    println!("Starting MoSQL...");

    let mongo_conn = export::setup("mongodb://localhost:27017", "mosql");
    assert!(mongo_conn.ping());

    let _ = export::generate_schema_mapping(mongo_conn, "test_collection");
    export::new_export();

    let conn_result = task::block_on(async {
        let database_url = "sqlite://data.db?mode=rwc";
        match async_function(&database_url).await {
            Ok(sqlite_conn) => return sqlite_conn,
            Err(err) => panic!("Error connecting to sqlite {}", err),
        }
    });
}

async fn async_function(database_url: &str) -> Result<DatabaseConnection, sea_orm::DbErr> {
    let connection = sea_orm::Database::connect(database_url).await?;
    Migrator::up(&connection, None).await?;

    return Ok(connection);
}
