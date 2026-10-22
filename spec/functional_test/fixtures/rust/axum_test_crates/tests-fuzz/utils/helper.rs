use axum::{routing::post, Router};

pub fn helper_router() -> Router {
    Router::new().route("/in-tests-fuzz", post(handler))
}

async fn handler() -> &'static str {
    "fuzz helper"
}
