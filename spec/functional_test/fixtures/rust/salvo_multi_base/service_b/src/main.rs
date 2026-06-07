use salvo::prelude::*;

mod consts;
mod handler;
mod routes;

fn route() -> Router {
    Router::new()
        .path("/b")
        .push(routes::build_shared_route())
}
