package core

import (
	"context"
	"errors"
	"fmt"
	"reflect"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var db *mongo.Database

type MongoValue struct {
	Value interface{}
	Type  string
}

type MongoType string

var MongoTypePrimitiveDateTime MongoType = "primitive.DateTime"
var MongoTypeMapInterface MongoType = "map[string]interface {}"
var MongoTypeString MongoType = "string"
var MongoTypeInt32 MongoType = "int32"
var MongoTypeInt64 MongoType = "int64"
var MongoTypeFloat64 MongoType = "float64"
var MongoTypeBool MongoType = "bool"
var MongoTypePrimitiveDecimal128 MongoType = "primitive.Decimal128"
var MongoTypePrimitiveObjectID MongoType = "primitive.ObjectID"

func stringID(ID interface{}) string {
	if ID != nil {
		switch v := ID.(type) {
		case string:
			return v
		case primitive.ObjectID:
			return v.Hex()
		default:
			return ""
		}
	}
	return ""
}

func InitMongoConnection(ctx context.Context, uri, dbName string) error {
	if db != nil {
		return errors.New("db already connected")
	}
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		return err
	}

	db = client.Database(dbName)
	return nil
}

func Insert(ctx context.Context, collection string, doc interface{}) (string, error) {
	result, err := db.Collection(collection).InsertOne(ctx, doc)
	if err != nil {
		return "", err
	}
	return stringID(result.InsertedID), nil
}

func Delete(ctx context.Context, collection, objectID string) (int64, error) {
	objID, err := primitive.ObjectIDFromHex(objectID)
	if err != nil {
		return 0, errors.New("invalid id")
	}

	filter := bson.D{{Key: "_id", Value: objID}}
	result, err := db.Collection(collection).DeleteOne(ctx, filter)
	if err != nil {
		return 0, err
	}
	return result.DeletedCount, nil
}

// Converts the mongo document for a collection to a flat key/value pair structure.
//
// For example:
//
// Input Mongo Document:
//
//	{
//	    "_id" : ObjectId("662c212535722ce52a911f20"),
//	    "attributes" : {
//	        "communicationChannels" : {
//	            "email" : "hello@mosql.io",
//	            "phone" : "111222333"
//	        },
//	        "communicationPrefs" : "SMS",
//	        "phoneNumberVerified" : true,
//	        "randomAttributes" : {
//	            "app_source" : "web",
//	            "channel" : "marketing",
//	            "signup_complete" : "false"
//	        },
//	        "skipTutorial" : false,
//	        "themeAttributes" : {
//	            "appearance" : "dark",
//	            "automatic" : false,
//	            "color" : "#cc00ff"
//	        }
//	    },
//	    "city" : "San Francisco",
//	    "email" : "hello@mosql.io",
//	    "state" : "CA",
//	    "intValue" : NumberInt(10),
//	    "longValue" : NumberLong(1000),
//	    "decimalValue" : NumberDecimal("10.363"),
//	    "dateValue" : ISODate("2024-03-19T06:01:17.171+0000")
//	}
//
// OUTPUT:
//
//	{
//	  "users._id": "BSON.ObjectId<6277f677b99d8078d17d5918>",
//	  "users.attributes.communicationChannels.email": "hello@mosql.io",
//	  "users.attributes.communicationChannels.phone": "111222333",
//	  "users.attributes.communicationPrefs": "SMS",
//	  "users.attributes.phoneNumberVerified": true,
//	  "users.attributes.randomAttributes.app_source": "web",
//	  ...
//	  .....
//	  "users.city": "San Francisco",
//	  "users.state: "CA"
//	}
//
// Here, 'users' prefix is a collection name to make key unique
func ToFlatDocument(ctx context.Context, collection string) map[string]MongoValue {

	filter := bson.D{}
	var res map[string]interface{}
	err := db.Collection(collection).FindOne(ctx, filter).Decode(&res)
	if err != nil {
		fmt.Println(err.Error())
		return nil
	}

	return toFlatDocument(collection, res)
}

func toFlatDocument(parentKey string, doc map[string]interface{}) map[string]MongoValue {
	finalMap := make(map[string]MongoValue)
	mapKeyValuesRecursively(parentKey, finalMap, doc)

	return finalMap
}

func mapKeyValuesRecursively(parentKey string, finalMap map[string]MongoValue, res map[string]interface{}) {
	for key, value := range res {
		if key == "_id" {
			key = "id"
		}

		key = fmt.Sprintf("%s.%s", parentKey, key)

		valueType := fmt.Sprintf("%s", reflect.TypeOf(value))

		switch MongoType(valueType) {
		case MongoTypeString,
			MongoTypeInt32,
			MongoTypeInt64,
			MongoTypeFloat64,
			MongoTypePrimitiveDecimal128,
			MongoTypeBool,
			MongoTypePrimitiveDateTime:

			finalMap[key] = getMongoValue(valueType, value)

		case MongoTypePrimitiveObjectID:
			finalMap[key] = getMongoValue(valueType, stringID(value))
		case MongoTypeMapInterface:
			mapKeyValuesRecursively(key, finalMap, value.(map[string]interface{}))
		default:
			fmt.Printf("**Type Not mapped for: Key: %s type(%s) mapped\n", key, valueType)
		}
	}
}

func getMongoValue(vtype string, value interface{}) MongoValue {
	return MongoValue{Value: value, Type: vtype}
}
