use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Connection::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Connection::Id)
                            .integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Connection::Name).string().not_null())
                    .col(
                        ColumnDef::new(Connection::ConnectionString)
                            .string()
                            .not_null(),
                    )
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Connection::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
pub enum Connection {
    Table,
    Id,
    Name,
    ConnectionString,
}
