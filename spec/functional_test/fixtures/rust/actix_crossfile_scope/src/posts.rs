use actix_web::{get, post, HttpResponse};

// Mounted at `/auth/v1` -> POST /auth/v1/posts
#[post("/posts")]
async fn create_post() -> HttpResponse {
    HttpResponse::Ok().body("created")
}

// Mounted at `/auth/v1` -> GET /auth/v1/posts
// `list` collides with `admin::list`; module-aware lookup must give
// this one `/auth/v1` and the admin one `/admin`.
#[get("/posts")]
async fn list() -> HttpResponse {
    HttpResponse::Ok().body("posts")
}
