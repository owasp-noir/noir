use axum::{routing::get, Router};

async fn list_orders() -> &'static str { "orders" }

pub fn router() -> Router {
    Router::new().route("/orders", get(list_orders))
}
