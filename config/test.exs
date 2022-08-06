import Config

config :core, schema_files_path: "/Users/puran/projects/mosql/apps/core/test/fixtures"

config :core, :postgres_opts,
  database: "mosql_db",
  username: "puran",
  password: "puran",
  hostname: "purans-mac-mini"
