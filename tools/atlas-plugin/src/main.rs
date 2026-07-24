mod commands;

use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "atlas-plugin",
    version,
    about = "Inspect, build, test, and migrate Atlas plugins"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Inspect {
        extension: PathBuf,
        #[arg(long, value_enum, default_value_t = OutputFormat::Human)]
        format: OutputFormat,
    },
    Build {
        extension: PathBuf,
        #[arg(short, long)]
        output: PathBuf,
    },
    Test {
        package: PathBuf,
    },
    Migrate {
        extension: PathBuf,
        #[arg(short, long)]
        output: PathBuf,
    },
}

#[derive(Clone, Copy, ValueEnum, Default)]
enum OutputFormat {
    #[default]
    Human,
    Json,
}

fn main() {
    let result = match Cli::parse().command {
        Command::Inspect { extension, format } => {
            match commands::inspect::run(&extension, matches!(format, OutputFormat::Json)) {
                Ok(true) => Ok(()),
                Ok(false) => std::process::exit(2),
                Err(error) => Err((2, error)),
            }
        }
        Command::Build { extension, output } => {
            commands::build::run(&extension, &output).map_err(|error| (3, error))
        }
        Command::Test { package } => commands::test::run(&package).map_err(|error| (4, error)),
        Command::Migrate { extension, output } => {
            commands::migrate::run(&extension, &output).map_err(|error| (3, error))
        }
    };
    if let Err((code, error)) = result {
        eprintln!("{error}");
        std::process::exit(code);
    }
}
