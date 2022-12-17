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

# Using an SRV URI also discovers all nodes of the deployment automatically
# Example: mongodb+srv://pss-mongo-cluster.xpbte.mongodb.net/mosql
mongo_srv_url = System.get_env("MONGO_SRV_URL") || "MONGO_SRV_URL not set"

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
  auth_source: "admin",
  auth_mechanism: "MONGODB-CR",
  pool_size: 3,
  name: :mongo
]

mongo_opts = url_mongo_opts
config :mosql, mongo_opts: mongo_opts

config :mosql, schema_files_path: "/Users/puran/projects/personal/mosql/test/fixtures"

# config :mosql,
#   producer_module: {MongoChangeStream, mongo_opts}

config :logger, :console,
  level: :debug,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:user_id]

config :mnesia,
  # Notice the single quotes
  dir: '.mnesia/#{Mix.env()}/#{node()}'

import_config "#{Mix.env()}.exs"
