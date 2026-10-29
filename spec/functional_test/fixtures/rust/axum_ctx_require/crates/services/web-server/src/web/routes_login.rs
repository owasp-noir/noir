use axum::routing::post;
use axum::Router;

async fn api_login_handler() -> &'static str {
    "login"
}

async fn api_logoff_handler() -> &'static str {
    "logoff"
}

pub fn routes(state: u64) -> Router {
    Router::new()
        .route("/api/login", post(api_login_handler))
        .route("/api/logoff", post(api_logoff_handler))
        .with_state(state)
}
