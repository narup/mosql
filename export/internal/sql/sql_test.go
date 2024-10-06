package sql

import (
	"fmt"
	"strings"
	"testing"

	"github.com/narup/mosql/export/internal/core"
	"github.com/stretchr/testify/assert"
)

func TestSQLGeneration(t *testing.T) {
	m1 := core.Mapping{
		SchemaID:             0,
		SourceFieldName:      "testFieldName",
		SourceType:           "string",
		DestinationFieldName: "test_field_name",
		DestinationType:      "VARCHAR(255)",
	}
	m2 := core.Mapping{
		SchemaID:             0,
		SourceFieldName:      "secondFieldName",
		SourceType:           "string",
		DestinationFieldName: "second_field_name",
		DestinationType:      "text",
	}

	m3 := core.Mapping{
		SchemaID:             0,
		SourceFieldName:      "numberFieldName",
		SourceType:           "decimal",
		DestinationFieldName: "number_field_name",
		DestinationType:      "numeric(10, 2)",
	}

	s := core.Schema{
		Namespace:  "sqltest",
		Collection: "test_collection",
		Table:      "test_table",
		PrimaryKey: "id",
		Version:    "1.0",
		Indexes:    "",
		Mappings:   []core.Mapping{m1, m2, m3},
	}

	actual1 := tableExistsSQL(s)
	expected1 := "SELECT table_name FROM information_schema.tables WHERE table_schema = 'sqltest' AND table_name = 'test_table'"
	assertSQLValues(t, expected1, actual1)

	actual2 := dropTableIfExistSQL(s)
	expected2 := "DROP TABLE IF EXISTS sqltest.test_table"
	assertSQLValues(t, expected2, actual2)

	actual3 := truncateTableSQL(s)
	expected3 := "TRUNCATE TABLE sqltest.test_table"
	assertSQLValues(t, expected3, actual3)

	actual4 := createTableIfExistsWithColumnsSQL(s)
	expected4 := "CREATE TABLE IF NOT EXISTS sqltest.test_table ( test_field_name VARCHAR(255), second_field_name TEXT, number_field_name NUMERIC(10, 2) )"
	assertSQLValues(t, expected4, actual4)

	fmt.Printf("****Test %s passed****\n", t.Name())
}

func assertSQLValues(t *testing.T, expected, actual string) {
	assert.EqualValues(t, sanitizeSQL(expected), sanitizeSQL(actual), "Expected and actual SQL output doesn't match")
}

func sanitizeSQL(q string) string {
	return strings.ReplaceAll(strings.Join(strings.Fields(q), " "), "\n", "")
}
