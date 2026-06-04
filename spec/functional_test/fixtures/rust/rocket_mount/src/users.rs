use rocket::get;

// mounted at /users -> GET /users
#[get("/")]
fn list() -> &'static str {
    "list"
}

// mounted at /users -> GET /users/{id}
#[get("/<id>")]
fn get_one(id: u32) -> String {
    format!("user {id}")
}
