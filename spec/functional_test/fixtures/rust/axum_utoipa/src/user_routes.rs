use crate::token_routes;
use crate::users;
use utoipa_axum::{router::OpenApiRouter, routes};

// Mounted at /api/v1/users. Lists its handlers via routes!() and nests a
// further collector at /tokens (recursive prefix composition).
pub fn create_routes() -> OpenApiRouter {
    OpenApiRouter::new()
        .routes(routes!(users::list_users))
        .routes(routes!(users::get_user))
        .nest("/tokens", token_routes::create_routes())
}
