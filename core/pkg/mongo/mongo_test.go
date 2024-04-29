package mongo

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

type testDocument struct {
	ID           interface{}       `bson:"_id"`
	Name         string            `bson:"name"`
	Email        string            `bson:"email"`
	City         string            `bson:"city"`
	State        string            `bson:"state"`
	IntValue     int32             `bson:"int_value"`
	LongValue    int64             `bson:"long_value"`
	DecimalValue float64           `bson:"decimal_value"`
	Active       bool              `bson:"active"`
	EmbeddedOne  *embeddedDocument `bson:"embed_one"`
	EmbeddedTwo  *embeddedDocument `bson:"embed_two"`
	DateTime     *time.Time        `bson:"date_time"`
}

type embeddedDocument struct {
	Source      string              `bson:"source"`
	Phone       string              `bson:"phone"`
	IsValid     bool                `bson:"is_valid"`
	SubEmbedDoc *subEmbededDocument `bson:"sub_embed_doc"`
}

type subEmbededDocument struct {
	DecimalValue float64    `bson:"decimal_value"`
	Color        string     `bson:"color"`
	DateValue    *time.Time `bson:"date_value"`
}

func TestToFlatDocument(t *testing.T) {
	test_setup()

	td := buildTestDocument()
	ctx := context.Background()
	coll := "test_collection"

	objectID, err := Insert(ctx, coll, td)
	if err != nil {
		assert.FailNow(t, "Test data insertion failed", err)
	}

	fmt.Printf("ObjectID: %s\n", objectID)

	flatMap := ToFlatDocument(ctx, coll)
	for key, value := range flatMap {
		fmt.Printf("'%s' : %+v\n", key, value)
	}

	result, err := Delete(ctx, coll, objectID)
	if err != nil {
		assert.FailNow(t, "Test data insertion failed", err)
	}

	assert.True(t, result == 1, "Failed, record should be deleted")

	println("test passed")
}

func buildTestDocument() *testDocument {
	td := new(testDocument)
	td.ID = primitive.NewObjectID()
	td.Name = "John Doe"
	td.Email = "john.doe@mosqltestemail.com"
	td.City = "San Francisco"
	td.State = "CA"
	td.IntValue = 20
	td.LongValue = 2000000000
	td.DecimalValue = 203.20
	td.Active = true
	t := time.Now()
	td.DateTime = &t

	ed1 := new(embeddedDocument)
	ed1.Source = "Mosql"
	ed1.IsValid = false
	ed1.Phone = "1112223333"

	sed1 := new(subEmbededDocument)
	sed1.Color = "#0d04cf"
	sed1.DateValue = &t

	ed1.SubEmbedDoc = sed1

	ed2 := new(embeddedDocument)
	ed2.Source = "AnotherSource"
	ed2.IsValid = true
	ed2.Phone = "1112223333"

	sed2 := new(subEmbededDocument)
	sed2.Color = "#0fffcc"
	sed2.DateValue = &t

	ed2.SubEmbedDoc = sed2

	td.EmbeddedOne = ed1
	td.EmbeddedTwo = ed2

	return td
}

func test_setup() {
	InitConnection(context.TODO(), "mongodb://localhost:27017/", "mosql")
}
