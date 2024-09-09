package core

import (
	"fmt"
	"math/rand"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestCreateExport(t *testing.T) {
	testSetup()

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

	savedExport, err := FindExportByNamespace(ex.Namespace)
	if err != nil {
		assert.Failf(t, "error loading saved export", "saved value should be loaded", err)
	}
	assert.NotNil(t, savedExport, "Saved export should not be nil")
	assert.True(t, savedExport.ID > 0, "export id should be non zero")

	assert.NotNil(t, savedExport.SourceConnection, "source connection cannot be nil")
	fmt.Printf("Source connection url: %s\n", savedExport.SourceConnection.ConnectionURI)
	assert.NotNil(t, savedExport.DestinationConnection, "destination connection cannot be nil")
	fmt.Printf("Destination connection url: %s\n", savedExport.DestinationConnection.ConnectionURI)

	assert.NotNil(t, savedExport.Creator, "Creator info cannot be nil")
	fmt.Printf("Created by: %s, %s", savedExport.Creator.UserName, savedExport.Creator.Email)
}

func testSetup() {
	deleteTestDBFile()
	Setup(true)
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
