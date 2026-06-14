use axum::{routing::get, Router};

// Mounted at `/admin` via a `let`-bound variable in main.rs.
pub fn admin_router() -> Router {
    Router::new().route("/users", get(list_users))
}

async fn list_users() {}
