use actix_web::{get, post, web, HttpResponse};

#[post("/login")]
async fn login(body: web::Json<String>) -> HttpResponse {
    UserService::login(body.into_inner());
    HttpResponse::Ok().finish()
}

#[get("/info")]
async fn info() -> HttpResponse {
    UserService::info();
    HttpResponse::Ok().finish()
}

pub fn init_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(login);
    cfg.service(info);
}
