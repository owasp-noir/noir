use utoipa_axum::{router::OpenApiRouter, routes};

#[utoipa::path(get, path = "/readme")]
pub async fn readme() {}

pub fn doc_routes() -> OpenApiRouter {
    OpenApiRouter::new().routes(routes!(readme))
}
