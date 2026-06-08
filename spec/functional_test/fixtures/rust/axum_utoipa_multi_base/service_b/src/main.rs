use utoipa_axum::router::OpenApiRouter;

mod routes;
mod users;

fn create_router() -> OpenApiRouter {
    OpenApiRouter::new().nest("/b", routes::create_routes())
}
