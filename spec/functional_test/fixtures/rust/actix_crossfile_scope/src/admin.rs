use actix_web::{get, HttpResponse};

// Mounted at `/admin` -> GET /admin/dashboard
#[get("/dashboard")]
async fn dashboard() -> HttpResponse {
    HttpResponse::Ok().body("dashboard")
}

// Mounted at `/admin` -> GET /admin/list
// Collides on leaf name with `posts::list`.
#[get("/list")]
async fn list() -> HttpResponse {
    HttpResponse::Ok().body("admin list")
}
