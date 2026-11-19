use axum::{routing::{get, post}, Router};

mod routes;

async fn health() -> &'static str { "ok" }
async fn list_users() -> &'static str { "ok" }
async fn create_user() -> &'static str { "ok" }
async fn stats() -> &'static str { "ok" }
async fn leaf() -> &'static str { "ok" }

fn leaf_routes() -> Router {
    Router::new().route("/leaf", get(leaf))
}

// Let-bound routers nested by name inside a fn that is itself nested:
// each route exists only under its full prefix.
fn api_router() -> Router {
    let users = Router::new()
        .route("/", get(list_users).post(create_user));
    let admin = Router::new().route("/stats", get(stats));

    Router::new()
        .nest("/users", users)
        .nest("/admin", admin)
}

#[tokio::main]
async fn main() {
    let deep = Router::new().nest("/x", leaf_routes());
    let app = Router::new()
        .route("/health", get(health))
        .nest("/api", api_router())
        .nest("/deep", deep)
        .nest("/v2", routes::v2_router());
    axum::serve(listener, app).await.unwrap();
}
