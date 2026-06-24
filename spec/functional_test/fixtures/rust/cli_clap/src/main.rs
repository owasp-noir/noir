use clap::{Parser, Subcommand};

#[derive(Parser)]
struct Cli {
    #[arg(short, long, env = "APP_VERBOSE")]
    verbose: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Serve {
        #[arg(long, env = "PORT")]
        port: u16,
    },
    Build {
        #[arg(long)]
        target: String,
    },
}

fn main() {
    let cli = Cli::parse();
    let token = std::env::var("API_TOKEN").unwrap();
    println!("{} {:?}", token, cli.verbose);
}
