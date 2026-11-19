use actix_web::{get, web, HttpResponse, Responder};

#[get("/recent")]
async fn recent() -> impl Responder { HttpResponse::Ok() }

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(recent);
}
