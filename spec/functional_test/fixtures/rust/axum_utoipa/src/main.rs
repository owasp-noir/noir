// utoipa-axum routing. Handlers carry their method + path in a
// `#[utoipa::path(...)]` attribute and are wired up with `routes!()` on an
// `OpenApiRouter`, which is mounted with `.nest("/api/v1/x", ...)`. The real
// URL is the nest prefix + the attribute path, composed across files.
use utoipa_axum::router::OpenApiRouter;

mod admin;
mod admin_routes;
mod token_routes;
mod tokens;
mod user_routes;
mod users;

fn create_router() -> OpenApiRouter {
    OpenApiRouter::new()
        .nest("/api/v1/users", user_routes::create_routes())
        .nest("/api/v1/admin", admin_routes::create_routes())
}
