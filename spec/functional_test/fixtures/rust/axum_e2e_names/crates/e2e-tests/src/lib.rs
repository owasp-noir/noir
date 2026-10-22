use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/in-e2e-tests-harness", get(handler))
}

async fn handler() -> &'static str {
    "harness"
}
