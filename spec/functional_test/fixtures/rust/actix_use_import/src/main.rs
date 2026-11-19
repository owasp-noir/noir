use actix_web::{web, App, HttpServer};

mod api;
mod handlers;
mod posts;
mod users;

use crate::posts::configure as posts_config;
use users::{user_config, list_all};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(web::scope("/users").configure(user_config))
            .service(web::scope("/posts").configure(posts_config))
            .service(web::scope("/all").service(list_all))
            .service(web::scope("/api").configure(api::config))
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
