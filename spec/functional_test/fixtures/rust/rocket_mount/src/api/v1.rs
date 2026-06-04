use rocket::{get, routes, Route};

// reached via api::all_routes() -> append v1::routes(); mounted at /api
// -> GET /api/status
#[get("/status")]
fn status() -> &'static str {
    "ok"
}

pub fn routes() -> Vec<Route> {
    routes![status]
}
