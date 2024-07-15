use std::error::Error;

use crate::core;
use log::{debug, info};
use sqlx::{postgres::PgPoolOptions, Pool};

pub struct PostgresClient {
    conn: Pool<sqlx::Postgres>,
}

pub async fn setup_postgres_client(uri: &str) -> PostgresClient {
    PostgresClient::new(uri).await
}

impl PostgresClient {
    pub async fn new(database_url: &str) -> Self {
        let conn_result = PgPoolOptions::new()
            .max_connections(5)
            .connect(database_url)
            .await;

        let conn = match conn_result {
            Ok(conn) => conn,
            Err(err) => panic!("Error connecting to postgres database: {}", err),
        };
        info!("Connected to postgres database");

        Self { conn }
    }

    pub async fn ping(&self) -> bool {
        sqlx::query("SELECT 1").execute(&self.conn).await.is_ok()
    }

    pub async fn table_exists(&self, schema: &core::Schema) -> Result<bool, Box<dyn Error>> {
        let sql = table_exists_sql(schema);
        let row = sqlx::query(sql.as_str()).fetch_optional(&self.conn).await?;
        Ok(row.is_some())
    }

    pub async fn drop_table(&self, schema: &core::Schema) -> Result<bool, Box<dyn Error>> {
        let drop_sql = drop_table_if_exists_sql(schema);
        let rows_affected = sqlx::query(drop_sql.as_str())
            .execute(&self.conn)
            .await?
            .rows_affected();
        Ok(rows_affected > 0)
    }
}

//generate a SQL to check if a table exists in the database
pub fn table_exists_sql(schema: &core::Schema) -> String {
    format!(
        r#"SELECT table_name FROM information_schema.tables
          WHERE table_schema = '{}' AND table_name = '{}'"#,
        schema.namespace, schema.sql_table
    )
}

pub fn drop_table_if_exists_sql(schema: &core::Schema) -> String {
    format!("DROPT TABLE IF EXISTS {}", full_table_name(schema))
}

//SQL for truncating table
pub fn truncate_table_sql(schema: &core::Schema) -> String {
    format!("TRUNCATE TABLE {}", full_table_name(schema))
}

pub fn create_table_if_not_exists(schema: &core::Schema) -> String {
    let column_definitions: String = schema
        .mappings
        .iter()
        .map(|m| format!("{} {}", m.destination_field_name, m.destination_field_type))
        .collect::<Vec<String>>()
        .join(",");

    format!(
        r#"CREATE TABLE IF NOT EXISTS {} ( {} ) "#,
        full_table_name(schema),
        column_definitions
    )
}

fn full_table_name(schema: &core::Schema) -> String {
    format!("{}.{}", schema.namespace, schema.sql_table)
}
