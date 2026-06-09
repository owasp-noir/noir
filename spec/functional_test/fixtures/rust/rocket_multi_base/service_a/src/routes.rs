use crate::users;
use rocket::{routes, Route};

pub fn routes() -> Vec<Route> {
    routes![users::list]
}
