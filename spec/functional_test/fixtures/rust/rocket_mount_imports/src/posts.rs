#[get("/recent")]
pub fn recent() -> &'static str { "ok" }

#[post("/")]
pub fn create() -> &'static str { "ok" }
