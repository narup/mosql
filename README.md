# MoSQL

[![Last Updated](https://img.shields.io/github/last-commit/narup/mosql.svg)](https://github.com/narup/mosql/commits/rust-version)

**This is still a work in progress. Not ready for production use**

# About 
CLI and web tool that helps you migrate MongoDB JSON data to Postgres. It supports both one time full data export as well as near real-time based on MongoDB Changestream. If you are looking to migrate your core application database or continue using MongoDB for your application but prefer using SQL for reporting MoSQL is your tool.

# Features 
- Full data export 
- Near real-time replication from Mongo to Postgres using Mongo changestream 
- Generate default schema mapping to map Mongo's collection and its keys to corresponding SQL table and its columns 
- Customize the export to include and exclude collections 
- Mappings can be fully customized to control the collection to SQL transformation - data type, field name etc
- Reporting - error and export progress and performance 
- Web admin to manage multiple export pipelines, meaning you can export to multiple SQL schemas from the same MongoDB source

# Getting Started

### 1. Initialize a new database export and configure
NOTE: export configuration can be changed later

 ``` $ mosql export init <namespace> ```
above command will prompt you for more details about the export

- `$ Source database name:`
- `$ Source database connection string:`
- `$ Destination database name:`
- `$ Destination database connection string:`
- `$ Collections to exclude (comma separated):`
- `$ Collections to include (comma separated, no value means include all collections):`
- `$ User name (optional):`
- `$ Email (optional):`
- `$ Save (Y/N - Press Y to save and N to change the export details):`
 If you press N and hit enter, you can change the details of the export. Press up or down arrow to skip through the details to update.
 If you press Y and if everything goes well, new export is created and you will see a success message with options for next actions you can take
   ```
    ✅ Export created with namespace <namespace>
    Now you can either generate a default schema mapping or run export with default mapping with following commands
     1) $ mosql export generate_mapping <namespace>
     2) $ mosql export run <namespace>
  ```
Directly running an export also generates a default schema mapping behind the scenes. But, it's recommended to generate a mapping and verify before running an export

### 2. Generate default schema mappings

 ``` $ mosql export generate_default_mappings ```
 this command helps generate the default mappings between the mongo collections to postgres tables which you can modify it. By default, collection keys are mapped to postgres table column name one-to-one. Some default convention followed for this default mapping
    - collection name is converted to snake case for SQL table name. e.g. collection `emailLogs` become `email_logs`
    - collection key also gets converted to snake case if they are camel case. e.g. `userId` becomes `user_id`
    - Data type conversion

| Mongo Type | Postgres Type |
|--|--|
| string | text |
| object id | text |
| double, decimal | numeric |
| int32 | integer |
| int64 | bigint |
| bool | boolean |
| Timestamp, DateTime | timestamp with time zone |
| default or unknown type | text |

### 3. MoSQL Admin Web Console

``` $ mosql admin ```
MoSQL comes with a web client to manage your export and other administrative tasks

## Running 
NixOS requires this command first in the terminal because of some openssl craziness (https://github.com/sfackler/rust-openssl/issues/1663) 
``` nix-shell -p libiconv openssl pkg-config``` 

## References

- https://github.com/dtzxporter/hydra - An actor framework inspired by Erlang/Elixir
