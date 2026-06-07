#[macro_use]
extern crate rocket;

mod routes;
mod users;

#[launch]
fn rocket() -> _ {
    rocket::build().mount("/b", routes::routes())
}
