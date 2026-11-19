#[macro_use]
extern crate rocket;

use rocket_okapi::{openapi, openapi_get_routes};

mod posts;

// Handlers brought in by `use` live in posts.rs, not here.
use posts::{create, recent};

// The Rocket guide's namespacing example: an inline module.
mod other {
    #[get("/world")]
    pub fn world() -> &'static str { "world" }
}

#[get("/hello")]
fn hello() -> &'static str { "hello" }

#[openapi]
#[get("/users")]
fn list_users() -> &'static str { "users" }

#[get("/a")]
fn a() -> &'static str { "a" }

// Mounted nowhere: keeps its bare path.
#[get("/loose")]
fn loose() -> &'static str { "loose" }

#[launch]
fn rocket() -> _ {
    let api_routes = routes![a];
    rocket::build()
        .mount("/posts", routes![recent, create])
        .mount("/hello", routes![hello, other::world])
        .mount("/api/v1", openapi_get_routes![list_users])
        .mount("/v1", api_routes)
}
