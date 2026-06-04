use actix_web::web;

async fn graphql() -> &'static str {
    "ok"
}

// Configured under web::scope("/api") in main.rs (direct fn reference) ->
// /api/graphql. An internal scope composes on top of the inherited prefix.
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/graphql").route(web::post().to(graphql)));
    cfg.service(web::scope("/v2").service(web::resource("/graphql").route(web::get().to(graphql))));
}
