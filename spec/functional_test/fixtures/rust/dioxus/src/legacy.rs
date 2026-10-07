use rocket::get;

#[get("/legacy")]
fn legacy() -> &'static str {
    "legacy"
}
