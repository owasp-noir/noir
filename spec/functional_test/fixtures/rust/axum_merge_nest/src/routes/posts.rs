use axum::{routing::{get, post}, Router};

async fn list() -> &'static str { "posts" }
async fn create() -> &'static str { "post" }

pub fn router() -> Router {
    Router::new().route("/posts", get(list).post(create))
}
