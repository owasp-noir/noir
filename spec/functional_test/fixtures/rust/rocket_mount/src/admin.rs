use rocket::{get, routes, Route};

// mounted at /admin (via the concat prefix) -> GET /admin/dashboard
#[get("/dashboard")]
fn dashboard() -> &'static str {
    "dashboard"
}

pub fn routes() -> Vec<Route> {
    routes![dashboard]
}
