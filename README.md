# MoSQL

MoSQL is an open source data pipeline built using [Elixir Broadway](https://elixir-broadway.org/) to migrate the MongoDB data from your MongoDB database cluster into a PostgreSQL database in near real-time using a [MongoDB Change Streams](https://www.mongodb.com/docs/manual/changeStreams/). If you run MongoDB as your application database in production but want to leverage SQL for offline reporting and analytics, MoSQL is the tool and service you need. MoSQL relies on the Erlang VM and supervision trees to provide a robust, reliable and fault tolerant migration system. Since Broadway enables concurrent data ingestion and processing and the outgoing data is also concurrent and can be batched this allows MoSQL to be fine tuned to achieve almost real-time replication capabilities.

The MoSQL Dashboard allows you to define schema mappings, inspect your migration processes, see system parameters, and track isolated replication failures in real-time.

**This is still a work in progress. Not ready for production use** 
