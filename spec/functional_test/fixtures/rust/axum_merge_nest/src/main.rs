use axum::{routing::get, Router};

mod routes;

async fn health() -> &'static str { "ok" }
async fn list_orders() -> &'static str { "orders" }
async fn list_items() -> &'static str { "items" }
async fn status() -> &'static str { "status" }

fn order_routes() -> Router {
    Router::new().route("/orders", get(list_orders))
}

fn item_routes() -> Router {
    Router::new().route("/items", get(list_items))
}

fn status_routes() -> Router {
    Router::new().route("/status", get(status))
}

// Nested under /v2 below: the routers it merges sit under /v2 too.
fn v2_routes() -> Router {
    Router::new().merge(order_routes()).merge(item_routes())
}

#[tokio::main]
async fn main() {
    // Per-module routers merged into one router, then nested.
    let api = Router::new()
        .merge(routes::users::router())
        .merge(routes::posts::router());

    let app = Router::new()
        .route("/health", get(health))
        .merge(status_routes())
        .nest("/api/v1", api)
        .nest("/inline", Router::new().merge(routes::tags::router()))
        .nest("/v2", v2_routes());
    axum::serve(listener, app).await.unwrap();
}
