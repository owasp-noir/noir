use axum::{routing::get, Router};

// Mounted through a let-bound `.with_state(...)` chain in main.rs via
// `nest_api_service`, matching aide/ApiRouter-style production code.
pub fn service_router() -> Router {
    Router::new().route("/status", get(status))
}

async fn status() {}
