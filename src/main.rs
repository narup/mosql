mod core;
mod mongo;
mod mosql;
use log::{info, LevelFilter};

fn main() {
    // Set the log level. This controls which messages get logged.
    log::set_max_level(LevelFilter::Debug);

    // Define a logger target for output. Here, we use stdout.
    let _ = simple_logger::SimpleLogger::new();

    info!("Starting MoSQL");

    let exporter = mosql::Exporter::new(
        "mosql", //namespace
        "mongo_to_postgres",
        "mongodb://localhost:27017/mosql",
        "postgres://...",
    );

    match exporter.generate_default_schema_mapping() {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    exporter.save();
}
