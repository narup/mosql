use futures::executor;

mod core;
mod mongo;
mod mosql;

fn main() {
    println!("Starting MoSQL...");

    //source database - mongo
    let mongo_conn = mongo::setup_connection("mongodb://localhost:27017", "mosql");
    assert!(mongo_conn.ping());

    //sqlite used for mosql specific data
    let sqlite_conn = core::setup_db_connection();
    assert!(sqlite_conn.ping());

    let _ = mosql::generate_schema_mapping(mongo_conn, "test_collection");

    let f = mosql::new_export(sqlite_conn);
    executor::block_on(f);
}
