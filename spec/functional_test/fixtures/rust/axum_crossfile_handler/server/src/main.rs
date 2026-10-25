mod handlers;

use axum::routing::{delete, get, post};
use axum::Router;
use handlers::login;
use my_domain::caps::axum::get as capabilities_endpoint;

fn main() {
    let _app: Router = Router::new()
        .route("/login", post(handlers::login))
        .route("/signin", post(login))
        .route("/records", post(handlers::push))
        .route("/store", delete(handlers::purge))
        .route("/list", get(handlers::list))
        .route("/search", post(handlers::search))
        .route("/loose", post(handlers::loose))
        .route("/generic", post(handlers::generic::<String>))
        .route("/capabilities", get(capabilities_endpoint));
}
