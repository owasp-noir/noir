use axum::{routing::get, Router};

async fn list() -> &'static str { "users" }
async fn stats() -> &'static str { "stats" }

pub fn user_routes() -> Router {
    Router::new().route("/", get(list))
}

pub fn admin_routes() -> Router {
    Router::new().route("/stats", get(stats))
}
