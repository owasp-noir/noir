use axum::{routing::get, Router};

async fn list() -> &'static str { "ok" }
async fn report() -> &'static str { "ok" }

fn user_router() -> Router {
    Router::new().route("/list", get(list))
}

fn report_router() -> Router {
    Router::new().route("/report", get(report))
}

// Nested from main.rs under /v2, and nests same-file router fns.
pub fn v2_router() -> Router {
    let reports = report_router();
    Router::new()
        .nest("/users", user_router())
        .nest("/reports", reports)
}
