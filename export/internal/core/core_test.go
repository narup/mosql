package core

import (
	"math/rand"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestCreateExport(t *testing.T) {
	Setup(true)

	ex := new(Export)
	ex.Namespace = randomString(8)
	ex.Type = "postgres"
	ex.SourceConnection = Connection{
		Name:          "mongo",
		ConnectionURI: "mongodb://localhost:27017/testdb",
	}
	ex.DestinationConnection = Connection{
		Name:          "postgres",
		ConnectionURI: "postgres://localhost:5432/destdb",
	}
	ex.IncludeCollections = "coll1,coll2"
	ex.ExcludeCollections = "coll10"

	ex.Creator = User{
		UserName: "testUser",
		Email:    "user@mosql.io",
	}
	ex.Updater = ex.Creator
	exportID, err := CreateExport(ex)
	if err != nil {
		assert.Failf(t, "Failed to create export", err.Error())
	}
	assert.True(t, exportID > 0, "test passed, export created")
}

func randomString(length int) string {
	// Seed the random number generator
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Characters to choose from
	chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

	// Create the random string
	result := make([]byte, length)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}

	return string(result)
}
