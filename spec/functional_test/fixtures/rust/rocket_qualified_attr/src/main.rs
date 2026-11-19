// No `#[macro_use] extern crate rocket;`: every macro is path-qualified.
#[derive(rocket::serde::Deserialize)]
struct NewUser {
    name: String,
}

#[rocket::get("/health")]
fn health() -> &'static str { "ok" }

#[rocket::post("/users", data = "<user>")]
fn create_user(user: rocket::serde::json::Json<NewUser>) -> &'static str { "ok" }

#[rocket::delete("/users/<id>")]
fn delete_user(id: u32) -> &'static str { "ok" }

#[rocket::route(PATCH, uri = "/users/<id>")]
fn patch_user(id: u32) -> &'static str { "ok" }

// Another crate's verb attribute is not a Rocket route.
#[other_web::get("/not-rocket")]
fn not_rocket() -> &'static str { "no" }

#[rocket::launch]
fn rocket() -> _ {
    rocket::build().mount("/api", rocket::routes![health, create_user, delete_user, patch_user])
}
