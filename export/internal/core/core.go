package core

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm/clause"
	"gorm.io/gorm/logger"

	"gorm.io/gorm"
)

type Export struct {
	gorm.Model
	Namespace               string `gorm:"unique,index"`
	Type                    string
	SourceConnectionID      uint
	DestinationConnectionID uint
	SourceConnection        Connection
	DestinationConnection   Connection
	Schemas                 []Schema
	ExcludeCollections      string `gorm:"type:text"`
	IncludeCollections      string `gorm:"type:text"`
	Creator                 User
	CreatorID               int64 `gorm:"index"`
	Updater                 User
	UpdaterID               int64
}

type Schema struct {
	gorm.Model
	ExportID   uint   `gorm:"index"`
	Namespace  string `gorm:"index:ns_collection"`
	Collection string `gorm:"index:ns_collection"`
	Table      string
	PrimaryKey string
	Version    string
	Indexes    string `gorm:"type:text"`
	Mappings   []Mapping
}

type Mapping struct {
	gorm.Model
	SchemaID             uint `gorm:"index"`
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
	UserName  string
	Email     string
	UserLogin UserLogin
}

type UserLogin struct {
	gorm.Model
	UserID                uint   `gorm:"index"`
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

func Setup(test bool) {
	if coreDB != nil {
		return
	}
	log.Println("Setting up core SQLite database for mosql")
	fileName := "mosql.db"
	if test {
		fileName = "mosql_test.db"
	}

	// gorm log levels - Silent, Error, Warn, Info
	db, err := gorm.Open(sqlite.Open(fileName), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
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

func CreateExport(export *Export) (uint, error) {
	tx := coreDB.Create(export)
	if tx.Error != nil {
		return 0, tx.Error
	}

	log.Printf("Export created %d", export.ID)
	return export.ID, nil
}

func CreateSchema(schema *Schema) (uint, error) {
	if schema.ExportID < 1 {
		return 0, errors.New("schema without export")
	}
	tx := coreDB.Create(schema)
	if tx.Error != nil {
		return 0, tx.Error
	}

	return schema.ID, nil
}

func FindExportByNamespace(namespace string) (*Export, error) {
	var export Export
	tx := coreDB.Preload(clause.Associations).Where("namespace = ?", namespace).First(&export)
	if errors.Is(tx.Error, gorm.ErrRecordNotFound) {
		return nil, errors.New("export not found")
	}

	return &export, nil
}

func FindAllExports() ([]*Export, error) {
	var exports []*Export
	result := coreDB.Find(&exports)

	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected == 0 {
		return nil, errors.New("no exports saved")
	}

	return exports, nil
}

func deleteTestDBFile() {
	_, err := os.ReadFile("./mosql_test.db")
	if err == nil {
		fmt.Println("Deleting old test db file")
		os.Remove("./mosql_test.db")
	}
}
