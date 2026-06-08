use actix_web::{get, web, HttpResponse};

#[get("/other")]
async fn other() -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(other);
}
