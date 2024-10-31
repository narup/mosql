package sql

import (
	"context"
	"errors"
	"fmt"
	"log"
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

// PrepareExport does 3 things
// 1. Truncate data from tables if exists
// 2. Create new tables, if not exists
// 3. Alter existing tables, if schema changed
func PrepareExport(ctx context.Context, export core.Export, db DB) error {
	for _, schema := range export.Schemas {
		createSQL := createTableIfNotExistsWithColumnsSQL(schema)
		res, err := db.conn.Exec(createSQL)
		if err != nil {
			return err
		}
		if res.RowsAffected() > 0 {
			log.Printf("Created a table %s", schema.Table)
		}

		truncateSQL := truncateTableSQL(schema)
		res, err = db.conn.Exec(truncateSQL)
		if err != nil {
			return err
		}
		log.Printf("Truncated %d rows from the table %s", res.RowsAffected(), schema.Table)

		if changed, changeType := hasSchemaChanged(schema); changed {
			// alter table
			log.Printf("Table %s changed %s", schema.Table, changeType)
		}
	}

	return nil
}

// check if schema definition/mapping changed than what we have in the
// SQL table. Changes supported are - column added/removed, data type and constraints
func hasSchemaChanged(schema core.Schema) (bool, string) {
	return false, "N/A"
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
func createTableIfNotExistsWithColumnsSQL(schema core.Schema) string {
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

func tableDefinitionSQL(schema core.Schema) string {
	q := `SELECT
              table_schema
             ,table_name
             ,column_name
             ,ordinal_position
             ,is_nullable
             ,data_type
             ,character_maximum_length
             ,numeric_precision
             ,numeric_precision_radix
             ,numeric_scale
             ,datetime_precision
      FROM
            information_schema.columns
      WHERE table_catalog = '%s' and table_name = '%s'`

	return fmt.Sprintf(q, schema.Namespace, schema.Table)
}
