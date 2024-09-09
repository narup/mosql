package export

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
	"github.com/narup/mosql/export/internal/core"
	"github.com/narup/mosql/export/internal/mongo"
)

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

// setup the mosql application
func Setup() {
	core.Setup(false)
}

// InitializeExport initlaizes the Mongo to SQL database export definition
// Note that this does not create the schema mappings by itself but to generate the default
// schema mappings for an export it needs to be initialzed first
func InitializeExport(ctx context.Context, namespace string, data InitData) (uint, error) {
	savedExport, err := core.FindExportByNamespace(namespace)
	if err != nil && err.Error() != "export not found" {
		return 0, err
	}
	if savedExport != nil && savedExport.ID > 0 {
		return 0, errors.New("export exists")
	}

	ce := new(core.Export)
	ce.Namespace = namespace
	ce.Type = fmt.Sprintf("mongo_to_%s", strings.ToLower(data.DestinationDatabaseType))
	ce.Schemas = make([]core.Schema, 0)

	ce.SourceConnection = core.Connection{
		Name:          data.SourceDatabaseName,
		ConnectionURI: data.SourceDatabaseConnectionString,
	}
	ce.DestinationConnection = core.Connection{
		Name:          data.DestinationDatabaseName,
		ConnectionURI: data.DestinationDatabaseConnectionString,
	}
	ce.Creator = core.User{
		Email:    data.Email,
		UserName: data.UserName,
	}
	ce.Updater = ce.Creator

	ce.ExcludeCollections = formatCollectionList(data.CollectionsToInclude)
	ce.IncludeCollections = formatCollectionList(data.CollectionsToInclude)

	return core.CreateExport(ce)
}

func GenerateSchemaMapping(ctx context.Context, namespace, collection string) error {
	flatMap := mongo.ToFlatDocument(ctx, collection)
	if flatMap == nil {
		return errors.New("schema mapping generation failed. Failed to generate key value map")
	}

	schema := new(core.Schema)
	schema.Namespace = namespace
	schema.Collection = collection
	schema.CreatedAt = time.Now()
	schema.Version = "1.0"

	return nil
}

func Start() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	uri := os.Getenv("DATABASE_URL")
	if uri == "" {
		log.Printf("You must set your 'DATABASE_URL' environment variable. See\n\t https://www.mongodb.com/docs/drivers/go/current/usage-examples/#environment-variable")
	}
	mongo.InitConnection(context.TODO(), uri, "mosql")
}

func formatCollectionList(listValue string) string {
	if listValue == "" {
		return ""
	}

	// remove the extra spaces between the separator
	list := strings.Split(listValue, ",")
	return strings.Join(list, ",")
}
