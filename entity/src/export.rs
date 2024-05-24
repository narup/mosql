//! `SeaORM` Entity. Generated by sea-orm-codegen 0.12.10

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Eq)]
#[sea_orm(table_name = "export")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i32,
    pub namespace: String,
    pub r#type: String,
    pub created_at: String,
    pub updated_at: String,
    pub source_connection_id: i32,
    pub destination_connection_id: i32,
    pub exclude_filters: Option<String>,
    pub include_filters: Option<String>,
    pub creator_id: i32,
    pub updator_id: i32,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::connection::Entity",
        from = "Column::DestinationConnectionId",
        to = "super::connection::Column::Id",
        on_update = "NoAction",
        on_delete = "Cascade"
    )]
    Connection2,
    #[sea_orm(
        belongs_to = "super::connection::Entity",
        from = "Column::SourceConnectionId",
        to = "super::connection::Column::Id",
        on_update = "NoAction",
        on_delete = "Cascade"
    )]
    Connection1,
    #[sea_orm(has_many = "super::schema::Entity")]
    Schema,
    #[sea_orm(
        belongs_to = "super::user::Entity",
        from = "Column::UpdatorId",
        to = "super::user::Column::Id",
        on_update = "NoAction",
        on_delete = "Cascade"
    )]
    User2,
    #[sea_orm(
        belongs_to = "super::user::Entity",
        from = "Column::CreatorId",
        to = "super::user::Column::Id",
        on_update = "NoAction",
        on_delete = "Cascade"
    )]
    User1,
}

impl Related<super::schema::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Schema.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
