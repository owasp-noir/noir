use clap::{Args, Parser, Subcommand};

#[derive(Parser)]
struct Cli {
    #[arg(long)]
    verbose: bool,
    #[command(subcommand)]
    service: Service,
}

#[derive(Subcommand)]
enum Service {
    Users(UsersArgs),
    Orders(OrdersArgs),
    Jobs(JobsArgs),
    // Inline variant holding the nested subcommand.
    Keys {
        #[arg(long)]
        store: String,
        #[command(subcommand)]
        action: KeysAction,
    },
    Verify {
        #[arg(long)]
        secret: String,
    },
}

// `Crud` is shared: it sits under both `users` and `orders`.
#[derive(Args)]
struct UsersArgs {
    #[arg(long)]
    tenant: String,
    #[command(subcommand)]
    action: Crud,
}

#[derive(Args)]
struct OrdersArgs {
    #[command(subcommand)]
    action: Crud,
}

// `jobs` runs on its own when no subcommand is given.
#[derive(Args)]
struct JobsArgs {
    #[arg(long)]
    all: bool,
    #[command(subcommand)]
    action: Option<JobsAction>,
}

#[derive(Subcommand)]
enum Crud {
    Get {
        #[arg(long)]
        id: String,
    },
    Delete,
}

#[derive(Subcommand)]
enum JobsAction {
    Run,
}

#[derive(Subcommand)]
enum KeysAction {
    Verify {
        #[arg(long)]
        keys_file: String,
    },
}

fn main() {
    let _cli = Cli::parse();
}
