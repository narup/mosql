pub use sea_orm_migration::prelude::*;

mod m20220101_000001_create_table_export;
mod m20240502_000159_create_table_user;
mod m20240502_161803_create_table_schema;
mod m20240502_211141_create_table_mapping;
mod m20240502_212411_create_table_connection;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20220101_000001_create_table_export::Migration),
            Box::new(m20240502_000159_create_table_user::Migration),
            Box::new(m20240502_161803_create_table_schema::Migration),
            Box::new(m20240502_211141_create_table_mapping::Migration),
            Box::new(m20240502_212411_create_table_connection::Migration),
        ]
    }
}
