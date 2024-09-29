package sql

import (
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx"
	"github.com/narup/mosql/export/internal/core"
)

type DB struct {
	conn *pgx.ConnPool
}

// InitConnection - connect to SQL destination datbase based on the database type
// posggres, mysql, etc
func InitConnection(dbType string, conn core.Connection) (DB, error) {
	if dbType == "postgres" {
		cfg := PostgresConfig{
			DBName: conn.Name,
			URL:    conn.ConnectionURI,
		}
		connPool, err := connectPostgresDB(&cfg)
		if err != nil {
			return DB{}, errors.Join(errors.New("postgres connection failed"), err)
		}
		return DB{conn: connPool}, nil
	}

	return DB{}, errors.New("database type not supported")
}

// Generates a SQL string for creating a table
//
// CREATE TABLE [IF NOT EXISTS] table_name (
//
//	column1 datatype(length) column_contraint,
//	column2 datatype(length) column_contraint,
//	column3 datatype(length) column_contraint,
//	  ...
//	  table_constraints
//	);
func createTableWithColumnsSQL(schema core.Schema) string {
	q := "CREATE TABLE IF NOT EXISTS %s ( %s )"

	columnDefinitions := make([]string, 0)
	for _, m := range schema.Mappings {
		defn := fmt.Sprintf("%s %s", m.DestinationFieldName, strings.ToUpper(m.DestinationType))
		if m.DestinationFieldName == schema.PrimaryKey {
			defn = fmt.Sprintf("%s PRIMARY KEY", defn)
		}
		columnDefinitions = append(columnDefinitions, defn)
	}

	return fmt.Sprintf(q, fullTableName(schema), strings.Join(columnDefinitions, ",\n"))
}

func dropTableIfExistSQL(schema core.Schema) string {
	return fmt.Sprintf("DROP TABLE IF EXISTS %s", fullTableName(schema))
}

// SQL for truncating table
func truncateTableSQL(schema core.Schema) string {
	return fmt.Sprintf("TRUNCATE TABLE %s", fullTableName(schema))
}

func getColumnDefinition(mapping core.Mapping) string {
	return fmt.Sprintf("%s %s", mapping.DestinationFieldName, mapping.DestinationType)
}

func fullTableName(schema core.Schema) string {
	return fmt.Sprintf("%s.%s", schema.Namespace, schema.Table)
}

func tableExistsSQL(schema core.Schema) string {
	q := `SELECT table_name FROM information_schema.tables
          WHERE table_schema = '%s' AND table_name = '%s'`
	return fmt.Sprintf(q, schema.Namespace, schema.Table)
}
