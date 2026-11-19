use actix_web::{get, web, HttpResponse, Responder};

#[get("/list")]
async fn list() -> impl Responder { HttpResponse::Ok() }

async fn manual() -> impl Responder { HttpResponse::Ok() }

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(list);
    cfg.route("/manual", web::get().to(manual));
}
