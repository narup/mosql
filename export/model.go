package export

import "time"

type InitData struct {
	SourceDatabaseName                  string
	SourceDatabaseConnectionString      string
	DestinationDatabaseName             string
	DestinationDatabaseConnectionString string
	DestinationDatabaseType             string
	CollectionsToExclude                string
	CollectionsToInclude                string
	UserName                            string
	Email                               string
	Save                                string
}
type Export struct {
	ID                    uint       `json:"id`
	Namespace             string     `json:"namespace"`
	Type                  string     `json:"type"`
	SourceConnection      Connection `json:"source_connection_name"`
	DestinationConnection Connection `json:"destination_connection_name"`
	Schemas               []string   `json:"schemas"`
	ExcludeCollections    string     `json:"exclude_collections"`
	IncludeCollections    string     `json:"include_collections"`
	Creator               User       `json:"creator"`
	Updater               User       `json:"updator"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

type Connection struct {
	Name          string    `json:"name"`
	ConnectionURI string    `json:"connection_uri"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type User struct {
	UserName  string    `json:"user_name"`
	FullName  string    `json:"full_name`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Schema struct {
	ID         uint      `json:"id"`
	ExportID   uint      `json:"export_id"`
	Namespace  string    `json:"namespace"`
	Collection string    `json:"collection"`
	Table      string    `json:"sql_table"`
	PrimaryKey string    `json:"primary_key"`
	Version    string    `json:"version"`
	Indexes    string    `json:"indexes"`
	Mappings   []Mapping `json:"mappings"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type Mapping struct {
	ID                   uint   `json:"id"`
	SchemaID             uint   `json:"schema_id"`
	SourceFieldName      string `json:"source_field_name"`
	DestinationFieldName string `json:"destination_filed_name"`
	SourceType           string `json:"source_field_type"`
	DestinationType      string `json:"destination_field_type"`
}
