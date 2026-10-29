use axum::routing::post;
use axum::Router;

async fn handler() -> &'static str {
    "ok"
}

pub fn loose() -> Router {
    Router::new().route("/api/loose", post(handler))
}

pub fn parse() -> Router {
    Router::new().route("/api/parse", post(handler))
}

pub fn logged() -> Router {
    Router::new().route("/api/logged", post(handler))
}

pub fn peek() -> Router {
    Router::new().route("/api/peek", post(handler))
}
