use actix_web::{get, web, HttpResponse, Responder};

pub mod admin;
pub mod users;

#[get("/ping")]
async fn ping() -> impl Responder { HttpResponse::Ok() }

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(ping)
        .service(web::scope("/users").configure(users::config));
    cfg.configure(admin::admin_routes);
}
