mod handlers;

use axum::routing::{delete, get, post};
use axum::Router;
use my_domain::caps::axum::get as capabilities_endpoint;

fn main() {
    let _app: Router = Router::new()
        .route("/login", post(handlers::login))
        .route("/records", post(handlers::push))
        .route("/store", delete(handlers::purge))
        .route("/capabilities", get(capabilities_endpoint));
}
