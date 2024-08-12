#![allow(dead_code)]

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

    pub async fn create_table(&self, schema: &core::Schema) -> Result<bool, Box<dyn Error>> {
        let create_sql = create_table_if_not_exists_sql(schema);

        info!("Creating table {}", schema.sql_table);
        debug!("{}", create_sql);
        sqlx::query(create_sql.as_str()).execute(&self.conn).await?;

        info!("table created successfully");
        Ok(true)
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
    format!("DROP TABLE IF EXISTS {}", full_table_name(schema))
}

//SQL for truncating table
pub fn truncate_table_sql(schema: &core::Schema) -> String {
    format!("TRUNCATE TABLE {}", full_table_name(schema))
}

pub fn create_table_if_not_exists_sql(schema: &core::Schema) -> String {
    let column_definitions: String = schema
        .mappings
        .iter()
        .map(get_column_definition)
        .collect::<Vec<String>>()
        .join(",");

    format!(
        r#"CREATE TABLE IF NOT EXISTS {} ( 
        id SERIAL PRIMARY KEY,
        {} 
        )"#,
        full_table_name(schema),
        column_definitions
    )
}

fn get_column_definition(m: &core::Mapping) -> String {
    format!("{} {}", m.destination_field_name, m.destination_field_type)
}

fn full_table_name(schema: &core::Schema) -> String {
    format!("{}.{}", schema.namespace, schema.sql_table)
}

#[cfg(test)]
mod tests {

    use crate::core;

    use super::*;

    #[test]
    fn test_sql_generators() {
        let mapping_1 = core::Mapping {
            id: Some(0),
            source_field_name: "fieldOne".to_string(),
            source_field_type: "string".to_string(),
            destination_field_name: "field_one".to_string(),
            destination_field_type: "text".to_string(),
            version: "1".to_string(),
        };
        let mapping_2 = core::Mapping {
            id: Some(0),
            source_field_name: "fieldTwo".to_string(),
            source_field_type: "number".to_string(),
            destination_field_name: "field_two".to_string(),
            destination_field_type: "numeric".to_string(),
            version: "1".to_string(),
        };

        let schema = core::Schema {
            namespace: "test_ns".to_string(),
            collection: "test_collection".to_string(),
            sql_table: "sql_test_table".to_string(),
            mappings: vec![mapping_1, mapping_2],
            ..Default::default()
        };

        let mut test_cases = Vec::<(&str, &str)>::new();
        test_cases.insert(0, ("truncate", "TRUNCATE TABLE test_ns.sql_test_table"));
        test_cases.insert(1, ("drop", "DROP TABLE IF EXISTS test_ns.sql_test_table"));
        test_cases.insert(2, ("table_exists", "SELECT table_name FROM information_schema.tables WHERE table_schema = 'test_ns' AND table_name = 'sql_test_table'"));
        test_cases.insert(3, ("create_table", "CREATE TABLE IF NOT EXISTS test_ns.sql_test_table ( id SERIAL PRIMARY KEY, field_one text,field_two numeric )"));

        test_cases.iter().for_each(|(test_case, expected_output)| {
            let actual_output: String = match *test_case {
                "truncate" => truncate_table_sql(&schema),
                "drop" => drop_table_if_exists_sql(&schema),
                "table_exists" => table_exists_sql(&schema),
                "create_table" => create_table_if_not_exists_sql(&schema),
                _ => "n/a".to_string(),
            };
            let actual_output = actual_output
                .split_whitespace()
                .collect::<Vec<&str>>()
                .join(" ");
            println!("Actual SQL output: {}", actual_output);

            assert_eq!(actual_output.as_str(), *expected_output, "should be equal");
        });
    }
}
