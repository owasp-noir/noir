use axum::{routing::get, Router};

async fn list() -> &'static str { "users" }
async fn show() -> &'static str { "user" }

pub fn router() -> Router {
    Router::new()
        .route("/users", get(list))
        .route("/users/{id}", get(show))
}
