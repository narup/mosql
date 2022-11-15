import Config

IO.puts("confing loaded from dev")

config :mosql, :postgres_opts,
  database: "mosql_db",
  username: "puran",
  password: "puran",
  hostname: "purans-mac-mini",
  name: :postgres

# url_mongo_opts = [
#   url: "mongodb+srv://localhost:27017/testdb",
#   appname: "mosql",
#   ssl: false,
#   pool_size: 3,
#   name: :mongo
# ]
# mongo_opts = url_mongo_opts
# config :mosql, mongo_opts: mongo_opts
