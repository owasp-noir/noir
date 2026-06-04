// Cross-function router composition. The root assembly mounts builder fns
// (defined in `routes/`) via `.push()` / `.unshift()`; those fns return
// nested Routers whose routes must inherit the `/api` base they're mounted
// under. An intermediate `.hoop()`-only router (no `.path()`) must pass the
// prefix straight through.
use salvo::prelude::*;

mod consts;
mod routes;

#[handler]
async fn index() {}
#[handler]
async fn auth() {}

fn route() -> Router {
    Router::new()
        .path("/api")
        .get(index) // GET /api
        .push(
            Router::new()
                .hoop(auth) // intermediate, no .path -> inherits /api
                .push(routes::build_system_route())
                .unshift(routes::build_admin_route()),
        )
}
