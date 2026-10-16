use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/in-e2e-harness", get(handler))
}

async fn handler() -> &'static str {
    "harness"
}
