package sql

import (
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx"
)

type PostgresConfig struct {
	URL         string
	DBName      string
	SSLMode     string
	SSLRootCert string
}

type PostgresDB struct {
	conn *pgx.ConnPool
}

type Tx struct {
	pgx.Tx
}

type Rows struct {
	pgx.Rows
}

var ErrNoRows = pgx.ErrNoRows

func connectPostgresDB(cfg *PostgresConfig) (*pgx.ConnPool, error) {
	pool, err := connect(cfg)
	// Fallback to ssl disable
	if err != nil && cfg.SSLMode != "disable" {
		cfg.SSLMode = "disable"
		cfg.SSLRootCert = ""
		pool, err = connect(cfg)
		if err != nil {
			return nil, err
		}
	}

	return pool, nil
}

// Check rows.Err() when reading a query as it is also possible an error may have occurred after receiving some rows
// but before the query has completed.
// Reference: https://pkg.go.dev/github.com/jackc/pgx/v4#Conn.Query
func (r Rows) NextRow() (bool, error) {
	if r.Next() {
		return true, nil
	}

	if err := r.Err(); err != nil {
		return false, err
	}

	return false, nil
}

// ExecQueryWithPool - executes query using a specific pool
func ExecQueryWithPool(pool *pgx.ConnPool, queryWithNamedParams string, params map[string]interface{}) (*Rows, error) {
	return execQueryWithPool(pool, queryWithNamedParams, params)
}

func execQueryWithPool(pool *pgx.ConnPool, queryWithNamedParams string, params map[string]interface{}) (*Rows, error) {
	paramArr := []interface{}{}
	count := 1

	for k, v := range params {
		queryWithNamedParams = strings.Replace(queryWithNamedParams, ":"+k, fmt.Sprintf("$%d", count), 1)
		paramArr = append(paramArr, v)
		count++
	}

	pr, err := pool.Query(queryWithNamedParams, paramArr...)
	if err != nil {
		return nil, err
	}

	return &Rows{Rows: *pr}, nil
}

func connect(cfg *PostgresConfig) (*pgx.ConnPool, error) {
	connURL := fmt.Sprintf("%s/%s?sslmode=%s", cfg.URL, cfg.DBName, cfg.SSLMode)

	if cfg.SSLMode != "disable" && strings.Trim(cfg.SSLRootCert, " ") != "" {
		connURL = fmt.Sprintf("%s&sslrootcert=%s", connURL, cfg.SSLRootCert)
	}

	connectionConfig, err := pgx.ParseURI(connURL)
	if err != nil {
		return nil, err
	}

	maxConnections := 50
	timeOut := 5 * time.Minute

	poolConfig := pgx.ConnPoolConfig{
		ConnConfig:     connectionConfig,
		MaxConnections: maxConnections,
		AfterConnect:   nil,
		AcquireTimeout: timeOut,
	}

	pgxPool, err := pgx.NewConnPool(poolConfig)
	if err != nil {
		return nil, err
	}

	return pgxPool, nil
}
