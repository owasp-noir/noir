use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/e2e/encrypt", get(handler))
}

async fn handler() -> &'static str {
    "encryption"
}
