mod core;
mod mongo;
mod mosql;
mod sql;
use log::info;

fn main() {
    // Define a logger target for output. Here, we use stdout.
    let _ = simple_logger::SimpleLogger::new()
        .with_level(log::LevelFilter::Info)
        .env()
        .init()
        .unwrap();

    info!("Starting MoSQL");

    let mut exporter = mosql::Exporter::new(
        "mosql", //namespace
        "mongo_to_postgres",
        "mongodb://localhost:27017/mosql",
        "postgres://...",
    );
    exporter.exclude_collections(vec![
        "collection1".to_string(),
        "collection2".to_string(),
        "collection3".to_string(),
    ]);
    exporter.include_collections(vec!["icollection1".to_string()]);
    exporter.set_creator("default@mosql.io", "Export Admin");

    match exporter.generate_default_schema_mapping() {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    exporter.save();
}
