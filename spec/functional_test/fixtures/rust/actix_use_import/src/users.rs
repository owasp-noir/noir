use actix_web::{get, web, HttpResponse, Responder};

#[get("/list")]
async fn list() -> impl Responder { HttpResponse::Ok() }

#[get("/everything")]
pub async fn list_all() -> impl Responder { HttpResponse::Ok() }

async fn stats() -> impl Responder { HttpResponse::Ok() }

pub fn user_config(cfg: &mut web::ServiceConfig) {
    cfg.service(list);
    cfg.route("/stats", web::get().to(stats));
}
