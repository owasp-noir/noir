use axum::{routing::get, Router};

// Singular `test-app` is not the plural test-crate convention; kept.
pub fn app() -> Router {
    Router::new().route("/test-app", get(handler))
}

async fn handler() -> &'static str {
    "test-app"
}
