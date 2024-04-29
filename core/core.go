package core

import (
	"context"
	"errors"
	"log"
	"os"
	"time"

	"github.com/joho/godotenv"
	"github.com/narup/mosql/core/pkg/model"
	"github.com/narup/mosql/core/pkg/mongo"
)

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
		return errors.New("Schema mapping generation failed. Failed to generate key value map")
	}

	schema := new(model.Schema)
	schema.Namespace = namespace
	schema.Collection = collection
	schema.CreatedAt = time.Now()
	schema.Version = "1.0"

	return nil
}
