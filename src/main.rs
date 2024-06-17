mod core;
mod mongo;
mod mosql;
mod sql;
use log::info;
use mosql::{Exporter, MoSQLError};
use std::io::{self, Write};
use structopt::StructOpt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    simple_logger::SimpleLogger::new()
        .with_level(log::LevelFilter::Info)
        .env()
        .init()
        .unwrap();

    info!("Starting MoSQL");

    let args = Cli::from_args();
    args.command.run().await?;
    Ok(())
}

#[derive(StructOpt)]
#[structopt(name = "mosql", about = "A CLI tool for managing your SQL tasks")]
struct Cli {
    #[structopt(subcommand)]
    command: Command,
}

#[derive(StructOpt, Debug)]
enum Command {
    #[structopt(
        name = "export",
        about = "Export related commands to initialize, list, update, save, and start different exports"
    )]
    Export(ExportCommand),
    #[structopt(name = "admin", about = "Start web admin console")]
    Admin,
}

#[derive(StructOpt, Debug)]
enum ExportCommand {
    #[structopt(about = "Initialize new export")]
    Init {
        #[structopt(help = "Export name")]
        export_name: String,
    },
    #[structopt(about = "Start an export with the given name")]
    Start {
        #[structopt(help = "Export name to start")]
        export_name: String,
    },
    #[structopt(about = "List all available exports")]
    List,
    #[structopt(about = "Generate default schema mapping files for a given export name")]
    GenerateDefaultMapping {
        #[structopt(help = "Unique export name")]
        export_name: String,
    },
    LoadSchemaMapping {
        #[structopt(help = "Schema mapping files directory path")]
        file_path: String,
        #[structopt(help = "Export name")]
        export_name: String,
    },
}

impl Command {
    async fn run(&self) -> Result<(), Box<dyn std::error::Error>> {
        match self {
            Command::Export(subcommand) => match subcommand {
                ExportCommand::Init { export_name } => export_init(export_name).await?,
                ExportCommand::GenerateDefaultMapping { export_name } => {
                    export_generate_default_mapping(export_name).await?
                }
                _ => println!("Command not supported"),
            },
            Command::Admin => println!("Web admin console running...."),
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

#[derive(Default)]
struct ExportData {
    source_db_name: Option<String>,
    source_db_uri: Option<String>,
    destination_db_name: Option<String>,
    destination_db_uri: Option<String>,
    exclude_collections: Vec<String>,
    include_collections: Vec<String>,
    user_name: Option<String>,
    email: Option<String>,
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
        true
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

    pub fn set_export_data_value(&self, export_data: &mut ExportData) {
        match self.info_type {
            ExportInfoType::SourceDatabaseName => {
                export_data.source_db_name = Some(self.user_input.to_owned());
            }
            ExportInfoType::SourceDatabaseConnString => {
                export_data.source_db_uri = Some(self.user_input.to_owned());
            }
            ExportInfoType::DestinationDatabaseName => {
                export_data.destination_db_name = Some(self.user_input.to_owned());
            }
            ExportInfoType::DestinationDatabaseConnString => {
                export_data.destination_db_uri = Some(self.user_input.to_owned());
            }
            ExportInfoType::IncludeCollections => {
                let collections: Vec<String> = self
                    .user_input
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect();
                export_data.include_collections = collections;
            }
            ExportInfoType::ExcludeCollections => {
                let collections: Vec<String> = self
                    .user_input
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect();
                export_data.exclude_collections = collections;
            }
            ExportInfoType::UserName => {
                export_data.user_name = Some(self.user_input.to_owned());
            }
            ExportInfoType::Email => {
                export_data.email = Some(self.user_input.to_owned());
            }
        }
    }
}

async fn export_init(namespace: &str) -> Result<(), Box<dyn std::error::Error>> {
    println!(
        "Initializing export '{}'. Please provide a few more details about the export:",
        namespace
    );

    let mut exporter = Exporter::new(namespace).await;

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

    let mut export_data = ExportData::default();
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
                    ei.set_export_data_value(&mut export_data);
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

    exporter.set_source_db(
        export_data.source_db_name.unwrap().as_str(),
        export_data.source_db_uri.unwrap().as_str(),
    );
    exporter.set_destination_db(
        export_data.destination_db_name.unwrap().as_str(),
        export_data.destination_db_uri.unwrap().as_str(),
    );
    exporter.include_collections(export_data.include_collections);
    exporter.exclude_collections(export_data.exclude_collections);
    exporter.set_creator(
        export_data.email.unwrap().as_str(),
        export_data.user_name.unwrap().as_str(),
    );

    match exporter.save().await {
        Err(err) => match err {
            MoSQLError::Mongo(error) => println!("{}", error),
            MoSQLError::Postgres(error) => println!("{}", error),
            MoSQLError::Persistence(error) => println!("{}", error),
            MoSQLError::SchemaPath(error) => println!("{}", error),
        },
        Ok(export) => {
            let export_json = serde_json::to_string_pretty(&export).unwrap();
            println!("Saved Export JSON: {}", export_json);
        }
    }

    Ok(())
}

async fn export_generate_default_mapping(
    namespace: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut exporter = Exporter::new(namespace).await;
    match exporter.generate_default_schema_mapping(Some("./")).await {
        Ok(_) => print!("success"),
        Err(err) => print!("Error {}", err),
    }

    Ok(())
}
