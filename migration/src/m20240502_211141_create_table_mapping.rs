use sea_orm_migration::prelude::*;

use crate::m20240502_161803_create_table_schema::Schema;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Mapping::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Mapping::Id)
                            .integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Mapping::SchemaId).integer().not_null())
                    .col(ColumnDef::new(Mapping::SourceFieldName).string().not_null())
                    .col(
                        ColumnDef::new(Mapping::DestinationFieldName)
                            .string()
                            .not_null(),
                    )
                    .col(ColumnDef::new(Mapping::SourceFieldType).string().not_null())
                    .col(
                        ColumnDef::new(Mapping::DestinationFieldType)
                            .string()
                            .not_null(),
                    )
                    .col(
                        ColumnDef::new(Mapping::Version)
                            .string()
                            .not_null()
                            .default("1.0"),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-mappings-schema-id")
                            .from(Mapping::Table, Mapping::SchemaId)
                            .to(Schema::Table, Schema::Id),
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Mapping::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Mapping {
    Table,
    Id,
    SchemaId,
    SourceFieldName,
    DestinationFieldName,
    SourceFieldType,
    DestinationFieldType,
    Version,
}
