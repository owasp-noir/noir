use actix_web::{get, HttpResponse};

// Mounted at `/auth` in main.rs -> GET /auth/me
#[get("/me")]
async fn get_me() -> HttpResponse {
    HttpResponse::Ok().body("me")
}

// Mounted at `/auth/v1` in main.rs -> GET /auth/v1/users
#[get("/users")]
async fn list_users() -> HttpResponse {
    HttpResponse::Ok().body("users")
}
