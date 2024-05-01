mod export;
mod mongo;

fn main() {
    println!("Starting MoSQL...");

    let conn = export::setup("mongodb://localhost:27017", "mosql");
    assert!(conn.ping());

    export::generate_schema_mapping(conn, "test_collection");

    export::new_export();
}
