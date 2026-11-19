use axum::{routing::get, Router};

async fn list() -> &'static str { "posts" }

pub fn post_routes() -> Router {
    Router::new().route("/", get(list))
}
