use actix_web::{web, App, HttpServer};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(web::scope("/api").service(api::users::list)))
        .bind("127.0.0.1:8080")?
        .run()
        .await
}
