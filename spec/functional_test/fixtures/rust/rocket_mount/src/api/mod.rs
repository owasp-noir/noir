use rocket::{get, routes, Route};

// alias re-export: `v1_routes` resolves to `v1::routes`
use crate::api::v1::routes as v1_routes;

mod v1;

// mounted at /api -> GET /api/ping
#[get("/ping")]
fn ping() -> &'static str {
    "pong"
}

// `all_routes()` is what main.rs mounts at /api. It aggregates its own
// `routes![ping]` plus the v1 sub-collector via the aliased append, so
// every leaf (ping + v1::status) inherits /api.
pub fn all_routes() -> Vec<Route> {
    let mut r = routes![ping];
    r.append(&mut v1_routes());
    r
}
