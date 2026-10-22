use axum::{routing::get, Router};

// `contests` merely ends in "tests"; a real feature crate.
pub fn app() -> Router {
    Router::new().route("/contests", get(handler))
}

async fn handler() -> &'static str {
    "contests"
}
