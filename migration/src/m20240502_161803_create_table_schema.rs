use crate::m20220101_000001_create_table_export::Export;
use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Schema::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Schema::Id)
                            .integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Schema::Namespace).string().not_null())
                    .col(ColumnDef::new(Schema::Collection).string().not_null())
                    .col(ColumnDef::new(Schema::SqlTable).string().not_null())
                    .col(ColumnDef::new(Schema::Version).string().not_null())
                    .col(ColumnDef::new(Schema::Indexes).text())
                    .col(ColumnDef::new(Schema::ExportId).integer().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-schemas-export-id")
                            .from(Schema::Table, Schema::ExportId)
                            .to(Export::Table, Export::Id),
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Schema::SqlTable).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
pub enum Schema {
    Table,
    Id,
    ExportId,
    Namespace,
    Collection,
    SqlTable,
    Version,
    Indexes,
}
