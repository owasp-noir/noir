use utoipa_axum::router::OpenApiRouter;

mod routes;
mod users;

fn create_router() -> OpenApiRouter {
    OpenApiRouter::new().nest("/a", routes::create_routes())
}
