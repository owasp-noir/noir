use axum::{routing::get, Router};

async fn list_users() -> &'static str { "users" }

pub fn router() -> Router {
    Router::new().route("/users", get(list_users))
}
