pub mod health;
pub mod users;

use axum::Router;

pub fn api_router() -> Router {
    Router::new().nest("/users", users::router())
}
