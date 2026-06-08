#[get("/items-b")]
pub fn list() -> &'static str {
    "b"
}
