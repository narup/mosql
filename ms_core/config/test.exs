import Config

config :mosql, schema_files_path: "./test/fixtures"

config :mosql, :postgres_opts,
  database: "mosql_db",
  username: "puran",
  password: "puran",
  hostname: "purans-mac-mini"
