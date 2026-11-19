use actix_web::{get, web, HttpResponse, Responder};

#[get("/stats")]
async fn stats() -> impl Responder { HttpResponse::Ok() }

pub fn admin_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(stats);
}
