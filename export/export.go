package export

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"github.com/joho/godotenv"
	"github.com/narup/mosql/export/internal/core"
	"github.com/narup/mosql/export/internal/mongo"
)

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

// GenerateSchemaMapping generate default schema mappings for an export with
// given namespace. This connects to the actual source Mongo database
func GenerateSchemaMapping(ctx context.Context, namespace, dirPath string) error {
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
	}
	if len(colls) == 0 {
		return errors.New("not enough collections")
	}

	schemaFilePaths := make([]string, 0)

	// for each collection generate schema and the mappings for collection keys
	for index, coll := range colls {
		mappings := make([]core.Mapping, 0)
		flatMap := mongo.ToFlatDocument(ctx, coll)
		if flatMap == nil {
			return errors.New("schema mapping generation failed. Failed to generate key value map")
		}

		for key, value := range flatMap {
			sqlType, err := mongo.SQLType(value.Type)
			if err != nil {
				return fmt.Errorf("type not mapped for field %s(%s)", key, value.Type)
			}
			m := core.Mapping{
				SourceFieldName:      key,
				SourceType:           value.Type,
				DestinationFieldName: toSnakeCase(key),
				DestinationType:      sqlType,
			}
			mappings = append(mappings, m)
		}

		schema := core.Schema{
			ExportID:   export.ID,
			Namespace:  namespace,
			Collection: coll,
			Table:      toSnakeCase(coll),
			Mappings:   mappings,
			Version:    "1.0-default-generated",
		}
		schemaID, err := core.CreateSchema(&schema)
		if err != nil {
			return fmt.Errorf("error saving schema %s. Error: %s", coll, err)
		}
		log.Printf("Generated schema for collection %s, id %d, index %d", coll, schemaID, index)

		// generate JSON mapping file for schema
		schemaJSON := toJSONSchemaModel(schema)
		schemaFileName := fmt.Sprintf("%s.json", coll)
		err = writeJSONToFile(schemaJSON, dirPath, schemaFileName)
		if err != nil {
			return fmt.Errorf("schema json mapping error: %s", err)
		}
		schemaFilePaths = append(schemaFilePaths, fmt.Sprintf("%s/%s", dirPath, schemaFileName))
	}

	// generate json file for export
	exportJSON := toJSONExportModel(export, schemaFilePaths)
	exportFileName := fmt.Sprintf("export_%s.json", namespace)
	err = writeJSONToFile(exportJSON, dirPath, exportFileName)
	if err != nil {
		return fmt.Errorf("export json mapping error: %s", err)
	}

	log.Printf("Export schema mappings generated")

	return nil
}

// LoadSchemaMapping loads the updated schema mapping after default mappings can be customized
// before running the export. Default mapping takes an opiniated view of type conversion and
// field names mapping. This helps overriding those default choices made by the mosql CLI tool
// for this to work export has to be initialized at least. Mappings can be handwritten provided
// it matches the expected format. But, generating a default mapping is a good way to go about
// defining a mapping
func LoadSchemaMapping(ctx context.Context, namespace, dirPath string) ([]string, error) {
	// track changes across export schemas
	changeset := make([]string, 0)

	savedExport, err := core.FindExportByNamespace(namespace)
	if err != nil {
		return changeset, err
	}

	exportData, err := readJSONFile(dirPath, fmt.Sprintf("%s_export.json", namespace), Export{})
	if err != nil {
		return changeset, err
	}

	var export Export
	if ex, ok := exportData.(Export); !ok {
		return changeset, errors.New("failed to load export mapping JSON file")
	} else {
		export = ex
	}
	if savedExport.ID != export.ID {
		return changeset, errors.New("export ID value doesn't match")
	}

	// handle diffs - updates the savedExport data model and changeset
	// changeset includes the list of everything that changed
	// updated is one way from export JSON based on schema mapping files to
	// data model
	changeset = handleExportDiff(savedExport, export, changeset)
	if len(changeset) == 0 {
		// no further action needed
		return changeset, nil
	}

	// save the updated changes to the database

	return changeset, nil
}

// ListExports list all the saved exports
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

// Start - starts the export process
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

func toJSONExportModel(export *core.Export, schemaFilePaths []string) Export {
	exportJSON := Export{
		ID:        export.ID,
		Namespace: export.Namespace,
		Type:      export.Type,
		SourceConnection: Connection{
			Name:          export.SourceConnection.Name,
			ConnectionURI: export.SourceConnection.ConnectionURI,
		},
		DestinationConnection: Connection{
			Name:          export.DestinationConnection.Name,
			ConnectionURI: export.DestinationConnection.ConnectionURI,
		},
		Creator: User{
			UserName: export.Creator.UserName,
			FullName: export.Creator.FullName,
			Email:    export.Creator.Email,
		},
		Updater: User{
			UserName: export.Updater.UserName,
			FullName: export.Updater.FullName,
			Email:    export.Updater.Email,
		},
		ExcludeCollections: export.ExcludeCollections,
		IncludeCollections: export.IncludeCollections,
		Schemas:            schemaFilePaths,
		CreatedAt:          export.CreatedAt,
		UpdatedAt:          export.UpdatedAt,
	}
	return exportJSON
}

func toJSONSchemaModel(schema core.Schema) Schema {
	js := Schema{
		ID:         schema.ID,
		ExportID:   schema.ExportID,
		Collection: schema.Collection,
		Table:      schema.Table,
		Version:    schema.Version,
		CreatedAt:  schema.CreatedAt,
		UpdatedAt:  schema.UpdatedAt,
	}

	return js
}

func toJSONMappingModel(mapping core.Mapping) Mapping {
	jm := Mapping{
		ID:                   mapping.ID,
		SchemaID:             mapping.SchemaID,
		SourceFieldName:      mapping.SourceFieldName,
		DestinationFieldName: mapping.DestinationFieldName,
		SourceType:           mapping.SourceType,
		DestinationType:      mapping.DestinationType,
	}

	return jm
}

func writeJSONToFile(data interface{}, dirPath, fileName string) error {
	// Create the directory if it doesn't exist
	if err := os.MkdirAll(dirPath, os.ModePerm); err != nil {
		return fmt.Errorf("failed to create directory: %v", err)
	}

	filePath := filepath.Join(dirPath, fileName)

	// Marshal the data into JSON
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %v", err)
	}

	// Write the JSON data to the file
	err = os.WriteFile(filePath, jsonData, 0644)
	if err != nil {
		return fmt.Errorf("failed to write file: %v", err)
	}

	return nil
}

func readJSONFile(dirPath, fileName string, data interface{}) (interface{}, error) {
	// Construct the full file path
	filePath := filepath.Join(dirPath, fileName)

	// Read the file
	file, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("error reading config file: %v", err)
	}

	// Unmarshal the JSON data into the struct
	err = json.Unmarshal(file, &data)
	if err != nil {
		return nil, fmt.Errorf("error unmarshaling config: %v", err)
	}

	return data, nil
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
	if listValue == "" {
		return []string{}
	}
	return strings.Split(listValue, ",")
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

func handleExportDiff(savedExport *core.Export, newExport Export, changeset []string) []string {
	changeset = handleConnectionDiff(savedExport, newExport, changeset)
	changeset = handleUserDiff(savedExport, newExport, changeset)

	if savedExport.IncludeCollections != newExport.IncludeCollections {
		changeset = append(changeset, "Include collection list chnaged")
		savedExport.IncludeCollections = formatCollectionList(newExport.IncludeCollections)
	}
	if savedExport.ExcludeCollections != newExport.ExcludeCollections {
		changeset = append(changeset, "Exclude collection list changed")
		savedExport.ExcludeCollections = formatCollectionList(newExport.ExcludeCollections)
	}
	return changeset
}

func handleUserDiff(savedExport *core.Export, newExport Export, changeset []string) []string {
	if savedExport.Creator.UserName != newExport.Creator.UserName {
		changeset = append(changeset, "Export creator user name changed")
		savedExport.Creator.UserName = newExport.Creator.UserName
	}
	if savedExport.Creator.FullName != newExport.Creator.FullName {
		changeset = append(changeset, "Export creator full name changed")
		savedExport.Creator.FullName = newExport.Creator.FullName
	}
	if savedExport.Creator.Email != newExport.Creator.Email {
		changeset = append(changeset, "Export creator email changed")
		savedExport.Creator.Email = newExport.Creator.Email
	}
	if savedExport.Updater.UserName != newExport.Updater.UserName {
		changeset = append(changeset, "Export updater user name changed")
		savedExport.Updater.UserName = newExport.Updater.UserName
	}
	if savedExport.Updater.FullName != newExport.Updater.FullName {
		changeset = append(changeset, "Export updater full name changed")
		savedExport.Updater.FullName = newExport.Updater.FullName
	}
	if savedExport.Updater.Email != newExport.Updater.Email {
		changeset = append(changeset, "Export updater email changed")
		savedExport.Updater.Email = newExport.Updater.Email
	}

	return changeset
}

func handleConnectionDiff(savedExport *core.Export, newExport Export, changeset []string) []string {
	if savedExport.SourceConnection.Name != newExport.SourceConnection.Name {
		changeset = append(changeset, "Source database connection name")
		savedExport.SourceConnection.Name = newExport.SourceConnection.Name
	}
	if savedExport.SourceConnection.ConnectionURI != newExport.SourceConnection.ConnectionURI {
		changeset = append(changeset, "Source database connection uri")
	}
	if savedExport.DestinationConnection.Name != newExport.DestinationConnection.Name {
		changeset = append(changeset, "Destination database connection name")
		savedExport.DestinationConnection.Name = newExport.DestinationConnection.Name
	}
	if savedExport.DestinationConnection.ConnectionURI != newExport.DestinationConnection.ConnectionURI {
		changeset = append(changeset, "Destination database connection uri")
	}

	return changeset
}
