mod core;
mod mongo;
mod mosql;

fn main() {
    println!("Starting MoSQL...");

    let exporter = mosql::Exporter::new(
        "mosql", //namespace
        "mongo_to_postgres",
        "mongodb://localhost:27017/mosql",
        "postgres://...",
    );

    match exporter.generate_schema_mapping("test_collection".to_string()) {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    exporter.save();
}
