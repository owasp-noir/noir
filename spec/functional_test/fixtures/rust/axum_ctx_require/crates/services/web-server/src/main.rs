mod web;

use lib_web::middleware::mw_auth::{mw_body_check, mw_ctx_loose, mw_ctx_peek, mw_ctx_require, mw_log};

use crate::web::routes_login;

use axum::{middleware, Router};

#[tokio::main]
async fn main() {
    let state = 0u64;

    let routes_rpc = web::routes_rpc::routes(state.clone())
        .route_layer(middleware::from_fn(mw_ctx_require));

    let routes_all = Router::new()
        .merge(routes_login::routes(state.clone()))
        .nest("/api", routes_rpc)
        .merge(web::routes_controls::loose().route_layer(middleware::from_fn(mw_ctx_loose)))
        .merge(web::routes_controls::parse().route_layer(middleware::from_fn(mw_body_check)))
        .merge(web::routes_controls::logged().route_layer(middleware::from_fn(mw_log)))
        .merge(web::routes_controls::peek().route_layer(middleware::from_fn(mw_ctx_peek)));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await.unwrap();
    axum::serve(listener, routes_all).await.unwrap();
}
