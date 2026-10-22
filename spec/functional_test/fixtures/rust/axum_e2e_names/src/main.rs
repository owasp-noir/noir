use axum::{routing::get, Router};

pub fn app() -> Router {
    Router::new().route("/real", get(handler))
}

async fn handler() -> &'static str {
    "real"
}
