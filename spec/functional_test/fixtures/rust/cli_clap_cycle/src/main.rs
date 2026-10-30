use clap::{Args, Parser, Subcommand};

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(subcommand)]
    Users(UsersMethod),
    #[command(subcommand)]
    Admin(AdminCmd),
}

#[derive(Subcommand)]
enum AdminCmd {
    Purge {
        #[arg(long)]
        all: bool,
    },
    /// Run any command as another user
    As(AsArgs),
}

#[derive(Args)]
struct AsArgs {
    #[arg(long)]
    user: String,
    #[command(subcommand)]
    inner: Commands,
}

#[derive(Subcommand)]
enum UsersMethod {
    Get {
        #[arg(long)]
        user_id: String,
    },
}

fn main() {}
