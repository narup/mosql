package sql

import (
	"fmt"
	"strings"
	"testing"

	"github.com/narup/mosql/export/internal/core"
	"github.com/stretchr/testify/assert"
)

func TestSQLGeneration(t *testing.T) {
	s := core.Schema{
		Namespace:  "sqltest",
		Collection: "test_collection",
		Table:      "test_table",
		PrimaryKey: "id",
		Version:    "1.0",
		Indexes:    "",
		Mappings:   []core.Mapping{},
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

	fmt.Printf("****Test %s passed****\n", t.Name())
}

func assertSQLValues(t *testing.T, expected, actual string) {
	assert.EqualValues(t, sanitizeSQL(expected), sanitizeSQL(actual), "Expected and actual SQL output doesn't match")
}

func sanitizeSQL(q string) string {
	return strings.ReplaceAll(strings.Join(strings.Fields(q), " "), "\n", "")
}
