use clap::{Args, Parser, Subcommand};

// The Parser struct's own name must not rename `Orders`, the first variant
// of the enum that follows.
#[derive(Parser)]
#[command(name = "tool")]
struct Cli {
    #[command(subcommand)]
    service: Service,
}

#[derive(Subcommand)]
enum Service {
    #[command(subcommand)]
    Orders(OrdersMethod),
    // Wraps an Args struct whose field holds the nested subcommand.
    Users(UsersArgs),
}

#[derive(Args)]
struct UsersArgs {
    #[command(subcommand)]
    method: UsersMethod,
}

#[derive(Subcommand)]
enum UsersMethod {
    Get {
        #[arg(long)]
        user_id: String,
    },
    Delete,
}

#[derive(Subcommand)]
enum OrdersMethod {
    Get {
        #[arg(long)]
        order_id: String,
    },
    Cancel,
}

fn main() {
    let _cli = Cli::parse();
}
