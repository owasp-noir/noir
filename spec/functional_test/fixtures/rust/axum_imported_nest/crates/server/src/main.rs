use axum::{routing::get, Router};
use utoipa_axum::router::OpenApiRouter;

mod docs;
mod posts;
mod users;

use crate::docs::doc_routes;
use crate::posts::post_routes;
use users::{admin_routes as admin, user_routes};

async fn health() -> &'static str { "ok" }

#[tokio::main]
async fn main() {
    // Router fns brought in with `use` (one renamed with `as`), a
    // hyphenated workspace crate and a crate whose package name differs
    // from its directory.
    let app = Router::new()
        .route("/health", get(health))
        .nest("/users", user_routes())
        .nest("/posts", post_routes())
        .nest("/admin", admin())
        .nest("/web", web_api::router())
        .nest("/acme", acme_api::router());
    let (docs, _) = OpenApiRouter::new().nest("/docs", doc_routes()).split_for_parts();
    let app = app.merge(docs);
    axum::serve(listener, app).await.unwrap();
}
