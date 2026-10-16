use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/in-e2e", get(handler))
}

async fn handler() -> &'static str {
    "e2e"
}
