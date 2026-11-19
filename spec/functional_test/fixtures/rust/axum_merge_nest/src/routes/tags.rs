use axum::{routing::get, Router};

async fn list() -> &'static str { "tags" }

pub fn router() -> Router {
    Router::new().route("/tags", get(list))
}
