use actix_web::{get, HttpResponse};

#[get("/list")]
pub async fn list() -> HttpResponse {
    HttpResponse::Ok().finish()
}
