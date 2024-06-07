mod core;
mod mongo;
mod mosql;
mod sql;
use log::info;
use std::io::{self, Write};
use structopt::StructOpt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Cli::from_args();
    args.command.run().await?;
    Ok(())
}

#[warn(dead_code)]
async fn another_main() {
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
    )
    .await;

    exporter.exclude_collections(vec![
        "collection1".to_string(),
        "collection2".to_string(),
        "collection3".to_string(),
    ]);
    exporter.include_collections(vec!["icollection1".to_string()]);
    exporter.set_creator("default@mosql.io", "Export Admin");

    match exporter.generate_default_schema_mapping().await {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    exporter.save();
}

#[derive(StructOpt)]
#[structopt(name = "mosql", about = "A CLI tool for managing your SQL tasks")]
struct Cli {
    #[structopt(subcommand)]
    command: Command,
}

#[derive(StructOpt)]
enum Command {
    #[structopt(name = "export-init", about = "Initialize the export")]
    ExportInit,
}

impl Command {
    async fn run(&self) -> Result<(), Box<dyn std::error::Error>> {
        match self {
            Command::ExportInit => {
                export_init().await?;
            }
        }
        Ok(())
    }
}

enum ExportInfoType {
    SourceDatabaseName,
    SourceDatabaseConnString,
    DestinationDatabaseName,
    DestinationDatabaseConnString,
    ExcludeCollections,
    IncludeCollections,
    UserName,
    Email,
}

struct ExportArgInput {
    prompt_text: String,
    user_input: String,
    info_type: ExportInfoType,
    required: bool,
}

impl ExportArgInput {
    pub fn validate(&self, input: String) -> bool {
        if self.required && input.len() <= 1 {
            println!("Value required. Try again!");
            return false;
        }
        return true;
    }

    pub fn input_field(&self) -> &str {
        match self.info_type {
            ExportInfoType::SourceDatabaseName => "source database name",
            ExportInfoType::SourceDatabaseConnString => "source database connection string",
            ExportInfoType::DestinationDatabaseName => "destination database name",
            ExportInfoType::DestinationDatabaseConnString => {
                "destination database connection string"
            }
            ExportInfoType::IncludeCollections => "collections to include",
            ExportInfoType::ExcludeCollections => "collections to exclude",
            ExportInfoType::UserName => "user name",
            ExportInfoType::Email => "user email",
        }
    }
}

async fn export_init() -> Result<(), Box<dyn std::error::Error>> {
    println!("Initializing export. Please provide a few more details about the export:");

    let mut export_info_list = vec![
        ExportArgInput {
            prompt_text: "Source database name".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::SourceDatabaseName,
            required: true,
        },
        ExportArgInput {
            prompt_text: "Source database connection string".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::SourceDatabaseConnString,
            required: true,
        },
        ExportArgInput {
            prompt_text: "Destination database name".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::DestinationDatabaseName,
            required: true,
        },
        ExportArgInput {
            prompt_text: "Destination database connection string".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::DestinationDatabaseConnString,
            required: true,
        },
        ExportArgInput {
            prompt_text: "Collections to exclude (comma separated)".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::ExcludeCollections,
            required: false,
        },
        ExportArgInput {
            prompt_text: "Collections to include (comma separated)".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::IncludeCollections,
            required: false,
        },
        ExportArgInput {
            prompt_text: "User name".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::UserName,
            required: false,
        },
        ExportArgInput {
            prompt_text: "User email".to_string(),
            user_input: String::new(),
            info_type: ExportInfoType::Email,
            required: false,
        },
    ];

    loop {
        for ei in export_info_list.iter_mut() {
            loop {
                let mut update_value = false;
                if ei.user_input.is_empty() {
                    print!("> {}:", ei.prompt_text.to_owned());
                } else {
                    update_value = true;
                    println!(
                        "Update current value: {} for {}. Press return to keep it same",
                        ei.user_input.to_owned(),
                        ei.input_field()
                    );
                    print!("> {}:", ei.prompt_text.to_owned());
                }

                io::stdout().flush().unwrap();
                let mut input = String::new();
                io::stdin()
                    .read_line(&mut input)
                    .expect("Error reading the input");

                if update_value && input.len() <= 1 {
                    //user didn't change existing value
                    input = ei.user_input.clone();
                }
                if ei.validate(input.clone()) {
                    ei.user_input = input.clone();
                    println!(">> {}", input);

                    //move to next input
                    break;
                } else {
                    continue;
                }
            }
        }

        print!("> Save(Y/N) - Press Y to save and N to change the export details:");

        let mut input = String::new();
        io::stdin()
            .read_line(&mut input)
            .expect("Error reading the input");

        if input == "Y" || input == "y" {
            break;
        }
    }

    for ei in export_info_list.iter() {
        println!("{}:{}", ei.prompt_text.clone(), ei.user_input.clone());
    }

    Ok(())
}
