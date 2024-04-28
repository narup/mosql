package core

import (
	"context"
	"log"
	"os"

	"github.com/joho/godotenv"
)

func Start() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	uri := os.Getenv("DATABASE_URL")
	if uri == "" {
		log.Printf("You must set your 'DATABASE_URL' environment variable. See\n\t https://www.mongodb.com/docs/drivers/go/current/usage-examples/#environment-variable")
	}
	InitMongoConnection(context.TODO(), uri, "mosql")
}
