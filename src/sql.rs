use crate::core;
use async_std::task;
use log::{debug, info};
use sqlx::{postgres::PgPoolOptions, Pool};

pub struct PostgresClient {
    conn: Pool<sqlx::Postgres>,
}

pub fn setup_postgres_client(uri: &str) -> PostgresClient {
    let conn = PostgresClient::new(uri);
    return conn;
}

impl PostgresClient {
    pub fn new(database_url: &str) -> Self {
        // Create a connection pool
        let conn = task::block_on(async {
            let conn_result = PgPoolOptions::new()
                .max_connections(5)
                .connect(&database_url)
                .await;

            match conn_result {
                Ok(sql_conn) => {
                    return sql_conn;
                }
                Err(err) => panic!("Error connecting to postgres database: {}", err),
            }
        });

        Self { conn }
    }

    pub fn ping(&self) -> bool {
        return task::block_on(async {
            match sqlx::query("SELECT 1").execute(&self.conn).await {
                Ok(_) => return true,
                Err(_) => return false,
            }
        });
    }
}

//generate a SQL to check if a table exists in the database
fn table_exists_sql(schema: core::Schema) -> String {
    return format!(
        r#"SELECT table_name FROM information_schema.tables
          WHERE table_schema = '{}' AND table_name = '{}'"#,
        schema.namespace, schema.sql_table
    );
}

fn truncate_table_sql(schema: core::Schema) -> String {
    format!("TRUNCATE TABLE {}", full_table_name(schema))
}

fn full_table_name(schema: core::Schema) -> String {
    format!("{}.{}", schema.namespace, schema.sql_table)
}
