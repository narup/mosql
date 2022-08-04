# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

alias MS.BroadwayMongo.Producer, as: MongoChangeStream

mongo_user = System.get_env("MONGO_USER") || raise "MONGO_USER env not set"
mongo_password = System.get_env("MONGO_PASSWORD") || raise "MONGO_PASSWORD env not set"

mongo_db_name = System.get_env("MONGO_DBNAME")
mongo_replica_url = System.get_env("MONGO_REPLICA_URL")

# Using an SRV URI also discovers all nodes of the deployment automatically
# Example: mongodb+srv://pss-mongo-cluster.xpbte.mongodb.net/mosql
mongo_srv_url = System.get_env("MONGO_SRV_URL")

mongo_replica_name =
  System.get_env("MONGO_REPLICA_NAME") || raise "MONGO_REPLICA_NAME env not set"

# By default, the driver will discover the deployment's topology and will connect to
# the replica set automatically, using either the seed list syntax or the URI syntax.
# Assuming the deployment has nodes at hostname1.net:27017, hostname2.net:27017 and
# hostname3.net:27017, either of the following invocations will discover the entire
# deployment: connection options for MongoDB with all the host and replica info
seed_mongo_opts = [
  seeds: String.split(mongo_replica_url),
  appname: "mosql",
  database: mongo_db_name,
  ssl: true,
  ssl_opts: [
    ciphers: ['AES256-GCM-SHA384'],
    versions: [:"tlsv1.2"],
    verify: :verify_none
  ],
  username: mongo_user,
  password: mongo_password,
  auth_source: "admin",
  auth_mechanism: "MONGODB-CR",
  set_name: mongo_replica_name,
  pool_size: 3
]

# srv uri option
url_mongo_opts = [
  url: mongo_srv_url,
  appname: "mosql",
  ssl: true,
  ssl_opts: [
    ciphers: ['AES256-GCM-SHA384'],
    versions: [:"tlsv1.2"],
    verify: :verify_none
  ],
  username: mongo_user,
  password: mongo_password,
  auth_source: "admin",
  auth_mechanism: "MONGODB-CR",
  pool_size: 3
]

mongo_opts = url_mongo_opts

config :core,
  ecto_repos: [MS.Repo]

config :core, :postgres_opts,
  database: "mosql_db",
  username: "puran",
  password: "puran",
  hostname: "purans-mac-mini"

config :core, mongo_opts: mongo_opts
config :core, schema_files_path: "/Users/puran/projects/personal/mosql/schema"

config :pipeline,
  producer_module: {MongoChangeStream, mongo_opts}

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:user_id]

import_config "#{Mix.env()}.exs"
