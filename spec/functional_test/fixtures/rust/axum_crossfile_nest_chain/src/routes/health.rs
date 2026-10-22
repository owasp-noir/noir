use axum::{routing::get, Router};

pub fn router() -> Router {
    Router::new().route("/healthz", get(|| async { "ok" }))
}
