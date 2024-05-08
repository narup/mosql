mod core;
mod mongo;
mod mosql;

fn main() {
    println!("Starting MoSQL...");

    //source database - mongo
    let mongo_conn = mongo::setup_connection("mongodb://localhost:27017", "mosql");
    assert!(mongo_conn.ping());

    //sqlite used for mosql specific data
    let sqlite_client = core::setup_sqlite_client();
    assert!(sqlite_client.ping());

    let _ = mosql::generate_schema_mapping(mongo_conn, "test_collection");
}
