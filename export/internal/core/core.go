package core

import (
	"database/sql"

	"gorm.io/gorm"
)

type Export struct {
	gorm.Model
	Namespace          string
	Type               string
	Source             Connection
	Destination        Connection
	Schemas            []Schema
	ExcludeCollections []string
	IncludeCollections []string
	Creator            User
	CreatorID          int64
	Updater            User
	UpdaterID          int64
}

type Schema struct {
	gorm.Model
	ExportID   int64
	Namespace  string
	Collection string
	Table      string
	PrimaryKey string
	Version    string
	Indexes    []string
	Mappings   []Mapping
}

type Mapping struct {
	gorm.Model
	SchemaID             int64
	SourceFieldName      string
	DestinationFieldName string
	SourceType           string
	DestinationType      string
}

type Connection struct {
	gorm.Model
	Name          string
	ConnectionURI string
}

type User struct {
	gorm.Model
	FullName  string
	UserName  *string
	Email     string
	UserLogin UserLogin
}

type UserLogin struct {
	gorm.Model
	UserID                int64
	Password              string // hashed!
	AccountActivatedDate  sql.NullTime
	LastPasswordResetDate sql.NullTime
	Status                string
	LoginType             string
	Source                string
	ExternalID            string
}

type LoginStatus string

const (
	LoginActive   LoginStatus = "Active"
	LoginDisabled LoginStatus = "Disabled"
)
