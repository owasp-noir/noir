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
    Loop(CycleA),
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
        #[arg(
            long,
            default_value = "http://localhost:8080"
        )]
        endpoint: String,
        #[arg(
            value_parser = ["fast", "slow"],
            long
        )]
        speed: String,
        #[arg(
            long,
            help = "Name of the subcommand to run"
        )]
        target: String,
    },
}

#[derive(Subcommand)]
enum CycleA {
    B(CycleB),
}

#[derive(Subcommand)]
enum CycleB {
    A(CycleA),
    Leaf,
}

fn main() {
    let _cli = Cli::parse();
}
