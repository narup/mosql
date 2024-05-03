use crate::m20240502_000159_create_table_user::User;
use crate::m20240502_212411_create_table_connection::Connection;
use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Export::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Export::Id)
                            .integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Export::Namespace).string().not_null())
                    .col(ColumnDef::new(Export::Type).string().not_null())
                    .col(ColumnDef::new(Export::CreatedAt).date_time().not_null())
                    .col(ColumnDef::new(Export::UpdatedAt).date_time().not_null())
                    .col(
                        ColumnDef::new(Export::SourceConnectionId)
                            .integer()
                            .not_null(),
                    )
                    .col(
                        ColumnDef::new(Export::DestinationConnectionId)
                            .integer()
                            .not_null(),
                    )
                    .col(ColumnDef::new(Export::ExcludeFilters).text())
                    .col(ColumnDef::new(Export::IncludeFilters).text())
                    .col(ColumnDef::new(Export::CreatorId).integer().not_null())
                    .col(ColumnDef::new(Export::UpdatorId).integer().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-exports-source-connection-id")
                            .from(Export::Table, Export::SourceConnectionId)
                            .to(Connection::Table, Connection::Id),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-exports-destination-connection-id")
                            .from(Export::Table, Export::DestinationConnectionId)
                            .to(Connection::Table, Connection::Id),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-exports-creator-id")
                            .from(Export::Table, Export::CreatorId)
                            .to(User::Table, User::Id),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-exports-updator-id")
                            .from(Export::Table, Export::UpdatorId)
                            .to(User::Table, User::Id),
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Export::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
pub enum Export {
    Table,
    Id,
    Namespace,
    Type,
    SourceConnectionId,
    DestinationConnectionId,
    ExcludeFilters,
    IncludeFilters,
    CreatorId,
    UpdatorId,
    CreatedAt,
    UpdatedAt,
}
