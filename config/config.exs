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
mongo_db_name = System.get_env("MONGO_DBNAME") || raise "MONGO_DBNAME env not set"
mongo_replica_url = System.get_env("MONGO_REPLICA_URL") || raise "MONGO_REPLICA_URL env not set"
mongo_replica_name = System.get_env("MONGO_REPLICA_NAME") || raise "MONGO_REPLICA_NAME env not set"

mongo_opts = [
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

config :core,
  ecto_repos: [MS.Repo]

config :core, MS.Repo,
  database: "mosql_db",
  username: "puran",
  password: "puran",
  hostname: "purans-mac-mini"

config :pipeline,
  producer_module: {MongoChangeStream, mongo_opts}

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
