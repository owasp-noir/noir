use crate::admin;
use utoipa_axum::{router::OpenApiRouter, routes};

// Mounted at /api/v1/admin.
pub fn create_routes() -> OpenApiRouter {
    OpenApiRouter::new().routes(routes!(admin::dashboard))
}
