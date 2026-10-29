use axum::routing::post;
use axum::Router;

async fn rpc_handler() -> &'static str {
    "rpc"
}

pub fn routes(state: u64) -> Router {
    Router::new()
        .route("/rpc", post(rpc_handler))
        .with_state(state)
}
