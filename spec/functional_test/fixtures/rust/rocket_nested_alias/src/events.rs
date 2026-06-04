use rocket::{post, routes, Route};

// mounted at /events via the aliased collector -> POST /events/collect
#[post("/collect")]
fn post_events_collect() -> &'static str {
    "ok"
}

pub fn build_routes() -> Vec<Route> {
    routes![post_events_collect]
}
