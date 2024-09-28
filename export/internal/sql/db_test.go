package sql

import (
	"testing"

	"github.com/narup/mosql/export/internal/core"
	"github.com/stretchr/testify/assert"
)

// this test might fail if postgres is not running locally
func TestDBPostgresConnection(t *testing.T) {
	conn := core.Connection{
		Name:          "testdb",
		ConnectionURI: "postgres://postgres:postgres123@localhost:5432",
	}
	db, err := InitConnection("postgres", conn)
	if err != nil {
		assert.Failf(t, "postgres connection failed %s", "should connect", err)
	}

	assert.True(t, db.conn.Stat().CurrentConnections > 0, "should be greater than 0")
	println("Postgres connection test passed")
}
