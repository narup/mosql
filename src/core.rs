use sea_orm::DatabaseConnection;

use async_std::task;
use migration::{Migrator, MigratorTrait};

pub struct Connection {
    pub conn: DatabaseConnection,
}

pub fn setup_db_connection() -> Connection {
    Connection::new()
}

impl Connection {
    pub fn new() -> Self {
        let sqlite_conn = task::block_on(async {
            let database_url = "sqlite://data.db?mode=rwc";
            match async_function(&database_url).await {
                Ok(sqlite_conn) => return sqlite_conn,
                Err(err) => panic!("Error connecting to sqlite {}", err),
            }
        });

        Self { conn: sqlite_conn }
    }

    pub fn ping(&self) -> bool {
        let res = task::block_on(async {
            match self.conn.ping().await {
                Ok(_) => return true,
                Err(_) => return false,
            }
        });

        return res;
    }
}

async fn async_function(database_url: &str) -> Result<DatabaseConnection, sea_orm::DbErr> {
    let connection = sea_orm::Database::connect(database_url).await?;
    Migrator::up(&connection, None).await?;

    return Ok(connection);
}
