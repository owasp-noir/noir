use actix_web::web;

async fn login() -> &'static str {
    "ok"
}

async fn logout() -> &'static str {
    "ok"
}

// Configured under web::scope("/auth") in main.rs -> /auth/login, /auth/logout.
pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/login").route(web::post().to(login)));
    cfg.service(web::resource("/logout").route(web::get().to(logout)));
}
