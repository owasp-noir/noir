// Plain `.nest("/p", X)` where the mounted sub-router's builder fn lives in
// ANOTHER file. Both the direct-call form (`webui::make_webui_router()`) and
// the `let`-bound form (`let r = admin::admin_router()`) are resolved, so the
// sub-router's own `.route()` calls compose the nest prefix instead of being
// emitted at the root.
use axum::{routing::get, Router};

mod admin;
mod service;
mod webui;

async fn root() {}

fn app() -> Router {
    let admin_router = admin::admin_router();
    let service_router = service::service_router().with_state(());

    Router::new()
        .route("/", get(root))
        .nest("/web", webui::make_webui_router())
        .nest("/admin", admin_router)
        .nest_api_service("/service", service_router)
}

fn main() {}
