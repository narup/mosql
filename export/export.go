package export

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode"

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

func GenerateSchemaMapping(ctx context.Context, namespace, filePath string) error {
	export, err := core.FindExportByNamespace(namespace)
	if err != nil {
		return err
	}

	conn := export.SourceConnection
	err = mongo.InitConnection(ctx, conn.ConnectionURI, conn.Name)
	if err != nil {
		return err
	}

	// fetch all the collection names in the source mongo db
	colls, err := mongo.Collections(ctx)
	if err != nil {
		return err
	}
	if len(colls) == 0 {
		return errors.New("no collections found")
	}

	// apply filters! if includes is non empty excludes are ignored
	includes := toCollectionList(export.IncludeCollections)
	excludes := toCollectionList(export.ExcludeCollections)

	if len(includes) > 0 {
		// delete all but what's in includes list
		colls = slices.DeleteFunc(colls, func(coll string) bool {
			return !slices.Contains(includes, coll)
		})
		// try to find if any collection in includes does not exist
		for _, i := range includes {
			if !slices.Contains(colls, i) {
				return fmt.Errorf("included collection `%s` not in collection list", i)
			}
		}
	} else if len(excludes) > 0 {
		colls = slices.DeleteFunc(colls, func(coll string) bool {
			return slices.Contains(excludes, coll)
		})
	} else {
		// ignore! includes & excludes are mutually exclusive
	}
	if len(colls) == 0 {
		return errors.New("not enough collections")
	}

	for index, coll := range colls {
		flatMap := mongo.ToFlatDocument(ctx, coll)
		if flatMap == nil {
			return errors.New("schema mapping generation failed. Failed to generate key value map")
		}

		schema := new(core.Schema)
		schema.Namespace = namespace
		schema.Collection = coll
		schema.Table = toSnakeCase(coll)
		schema.CreatedAt = time.Now()
		schema.Mappings = make([]core.Mapping, 0) // populate mappings
		schema.Version = "1.0"

		log.Printf("Generated schema for collection %s, index %d", coll, index)
	}

	return nil
}

func ListExports(ctx context.Context) ([]string, error) {
	finalList := make([]string, 0)

	exports, err := core.FindAllExports()
	if err != nil {
		return finalList, err
	}

	for _, ex := range exports {
		finalList = append(finalList, ex.Namespace)
	}
	return finalList, nil
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

func toCollectionList(listValue string) []string {
	if list == "" {
		return []string{}
	}
	return strings.Split(list, ",")
}

func toSnakeCase(s string) string {
	// Check if the string is already in lower case (with or without underscores)
	if isLowerCase(s) {
		return s
	}

	// Convert to snake case
	var result strings.Builder
	for i, r := range s {
		if i > 0 && unicode.IsUpper(r) {
			result.WriteRune('_')
		}
		result.WriteRune(unicode.ToLower(r))
	}

	// Remove any consecutive underscores
	re := regexp.MustCompile(`_+`)
	return re.ReplaceAllString(result.String(), "_")
}

func isLowerCase(s string) bool {
	// Check if the string contains only lowercase letters, numbers, and underscores
	for _, r := range s {
		if !unicode.IsLower(r) && !unicode.IsDigit(r) && r != '_' {
			return false
		}
	}
	return true
}
