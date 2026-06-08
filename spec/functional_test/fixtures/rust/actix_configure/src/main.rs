// A scope delegates its body to a `configure` fn defined in another file:
// `web::scope("/auth").configure(|cfg| auth::configure_routes(cfg))` and
// `web::scope("/api").configure(api::configure)`. The builder routes live in
// those fns (auth.rs / api.rs) with no visible scope, so they must inherit
// the `/auth` / `/api` prefix from the configure call site.
use actix_web::{web, App, HttpServer};

mod api;
mod auth;
mod other;
mod todo;
mod user;

use crate::todo::controllers as td_controllers;
use crate::user::controllers as u_controllers;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(web::scope("/auth").configure(|cfg| auth::configure_routes(cfg)))
            .service(web::scope("/api").configure(api::configure))
            .service(
                web::scope("/v1")
                    .service(web::scope("/todos").configure(td_controllers::init_routes))
                    .service(web::scope("/user").configure(u_controllers::init_routes)),
            )
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
