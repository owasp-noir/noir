use crate::tokens;
use utoipa_axum::{router::OpenApiRouter, routes};

// Nested under /api/v1/users at /tokens -> /api/v1/users/tokens.
pub fn create_routes() -> OpenApiRouter {
    OpenApiRouter::new().routes(routes!(tokens::list_tokens))
}
