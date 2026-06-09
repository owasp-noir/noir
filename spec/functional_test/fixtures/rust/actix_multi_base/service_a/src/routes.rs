use actix_web::web;

async fn status() -> &'static str {
    "a"
}

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/status").route(web::get().to(status)));
}
