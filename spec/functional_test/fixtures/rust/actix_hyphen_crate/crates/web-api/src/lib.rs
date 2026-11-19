use actix_web::{get, web, HttpResponse, Responder};

#[get("/users")]
async fn list_users() -> impl Responder { HttpResponse::Ok() }

async fn stats() -> impl Responder { HttpResponse::Ok() }

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(list_users);
    cfg.route("/stats", web::get().to(stats));
}
