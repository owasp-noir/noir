use clap::{Parser, Subcommand};

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Pen(PenCmd),
    #[command(name = "__internal", hide = true)]
    Internal,
}

#[derive(Subcommand)]
enum PenCmd {
    Open,
    Close {
        #[arg(
            long,
            value_name = "GRAMS"
        )]
        amount: u32,
    },
}

fn main() {
    let _cli = Cli::parse();
}
