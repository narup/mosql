mod core;
mod mongo;
mod mosql;

fn main() {
    println!("Starting MoSQL...");

    let exporter = mosql::Exporter::new("mosql".to_string(), "postgres".to_string());

    match exporter.generate_schema_mapping("test_collection") {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    exporter.save();
}
