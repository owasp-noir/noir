use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/e2e/keys/upload", get(handler))
}

async fn handler() -> &'static str {
    "keys"
}
