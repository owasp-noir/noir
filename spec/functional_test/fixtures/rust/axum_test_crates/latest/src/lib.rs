use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/latest", get(handler))
}

async fn handler() -> &'static str {
    "latest"
}
