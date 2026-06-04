// aide's ApiRouter (OpenAPI companion for axum), as used by svix and
// many production axum APIs. Exercises `.api_route`, `.api_route_with`
// (with the operation-transform closure), the `*_with` verb
// constructors, and `.nest_api_service` prefix composition.
use aide::axum::{
    routing::{get_with, post_with},
    ApiRouter,
};
use aide::transform::TransformOperation;
use axum::routing::{get, post};

async fn ping() {}
async fn redrive() {}
async fn list_apps() {}
async fn create_app() {}

fn redrive_op(op: TransformOperation) -> TransformOperation {
    op.summary("redrive")
}

fn v1_router() -> ApiRouter {
    ApiRouter::new().api_route("/app", get(list_apps).post(create_app))
}

pub fn router() -> ApiRouter {
    ApiRouter::new()
        .api_route("/health/ping", get(ping).head(ping))
        .api_route_with(
            "/admin/redrive",
            post_with(redrive, redrive_op),
            |op| op.tag("Admin"),
        )
        .nest_api_service("/api/v1", v1_router())
}

fn main() {}
