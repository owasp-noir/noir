use crate::users;
use utoipa_axum::{router::OpenApiRouter, routes};

pub fn create_routes() -> OpenApiRouter {
    OpenApiRouter::new().routes(routes!(users::list))
}
