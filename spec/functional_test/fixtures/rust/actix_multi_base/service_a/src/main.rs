use actix_web::{web, App, HttpServer};

mod routes;
mod users;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().service(
            web::scope("/a")
                .service(users::list)
                .configure(routes::configure),
        )
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
