use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/in-playwright-harness", get(handler))
}

async fn handler() -> &'static str {
    "harness"
}
