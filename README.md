# MoSQL

[![Last Updated](https://img.shields.io/github/last-commit/narup/mosql.svg)](https://github.com/narup/mosql/commits/master)

MoSQL is an open source data pipeline built using [Elixir Broadway](https://elixir-broadway.org/) to migrate the MongoDB data from your MongoDB database cluster into a PostgreSQL database. It supports one-time full export and [MongoDB Change Streams](https://www.mongodb.com/docs/manual/changeStreams/) based near real-time export. If you run MongoDB as your application database in production but want to leverage SQL for offline reporting and analytics, MoSQL is the tool and service you need. MoSQL relies on the Erlang VM and supervision trees to provide a robust, reliable and fault tolerant migration system

**This is still a work in progress. Not ready for production use**
