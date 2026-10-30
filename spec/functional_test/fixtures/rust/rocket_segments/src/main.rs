#[macro_use]
extern crate rocket;

use std::path::PathBuf;

// `<name..>` matches zero or more segments (vaultwarden serves its web vault
// with `#[get("/<p..>", rank = 10)]`).
#[get("/<p..>", rank = 10)]
async fn web_files(p: PathBuf) -> String {
    p.display().to_string()
}

#[get("/static/<file..>")]
async fn assets(file: PathBuf) -> String {
    file.display().to_string()
}

#[get("/users/<id>/files/<rest..>")]
async fn user_files(id: u32, rest: PathBuf) -> String {
    format!("{} {}", id, rest.display())
}

#[launch]
fn rocket() -> _ {
    rocket::build().mount("/", routes![web_files, assets, user_files])
}
