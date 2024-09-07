package export

import (
	"context"
	"errors"
	"log"
	"os"
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

func InitializeExport(ctx context.Context, data InitData) error {
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
