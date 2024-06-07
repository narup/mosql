use crate::core;
use log::{debug, info};
use sqlx::{postgres::PgPoolOptions, Pool};

pub struct PostgresClient {
    conn: Pool<sqlx::Postgres>,
}

pub async fn setup_postgres_client(uri: &str) -> PostgresClient {
    let conn = PostgresClient::new(uri).await;
    return conn;
}

impl PostgresClient {
    pub async fn new(database_url: &str) -> Self {
        let conn_result = PgPoolOptions::new()
            .max_connections(5)
            .connect(&database_url)
            .await;

        match conn_result {
            Ok(conn) => {
                return Self { conn };
            }
            Err(err) => panic!("Error connecting to postgres database: {}", err),
        }
    }

    pub async fn ping(&self) -> bool {
        match sqlx::query("SELECT 1").execute(&self.conn).await {
            Ok(_) => return true,
            Err(_) => return false,
        }
    }

    pub async fn execute_query(&self, sql: &str) {
        debug!("executing sql: {}", sql);
        let query_result = sqlx::query(sql).execute(&self.conn).await;
        match query_result {
            Ok(res) => println!("rows effected: {}", res.rows_affected()),
            Err(err) => println!("error: {}", err),
        }
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
