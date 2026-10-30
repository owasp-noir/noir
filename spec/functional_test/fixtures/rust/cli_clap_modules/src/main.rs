use clap::{Parser, Subcommand};

mod build;
mod run;

// The Parser shares its name with the per-command `run::Args` and
// `build::Args`; those payloads must not resolve to this struct.
#[derive(Parser)]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Run(run::Args),
    Build(build::Args),
    Status {
        #[arg(long)]
        json: bool,
    },
}

fn main() {
    let _ = Args::parse();
}
