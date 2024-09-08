package core

import (
	"database/sql"
	"errors"
	"fmt"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm/clause"

	"gorm.io/gorm"
)

type Export struct {
	gorm.Model
	Namespace          string `gorm:"unique,index"`
	Type               string
	Source             Connection
	Destination        Connection
	Schemas            []Schema
	ExcludeCollections []string
	IncludeCollections []string
	Creator            User
	CreatorID          int64 `gorm:"index"`
	Updater            User
	UpdaterID          int64
}

type Schema struct {
	gorm.Model
	ExportID   int64  `gorm:"index"`
	Namespace  string `gorm:"index:ns_collection"`
	Collection string `gorm:"index:ns_collection"`
	Table      string
	PrimaryKey string
	Version    string
	Indexes    []string
	Mappings   []Mapping
}

type Mapping struct {
	gorm.Model
	SchemaID             int64 `gorm:"index"`
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
	FullName  *string
	UserName  *string
	Email     string
	UserLogin UserLogin
}

type UserLogin struct {
	gorm.Model
	UserID                int64  `gorm:"index"`
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

var coreDB *gorm.DB

func init() {
	db, err := gorm.Open(sqlite.Open("mosql.db"), &gorm.Config{})
	if err != nil {
		panicMsg := fmt.Sprintf("error starting mosql. error %s", err)
		panic(panicMsg)
	}

	// setup migrations
	db.AutoMigrate(&Export{})
	db.AutoMigrate(&Schema{})
	db.AutoMigrate(&Mapping{})
	db.AutoMigrate(&Connection{})
	db.AutoMigrate(&User{})
	db.AutoMigrate(&UserLogin{})

	coreDB = db
}

func FindExportByNamespace(namespace string) (*Export, error) {
	var export Export
	tx := coreDB.Preload(clause.Associations).Where("namespace = ?", namespace).First(&export)
	if errors.Is(tx.Error, gorm.ErrRecordNotFound) {
		return nil, errors.New("export not found")
	}

	return &export, nil
}
