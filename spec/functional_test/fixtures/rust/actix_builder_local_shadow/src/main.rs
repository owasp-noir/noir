use actix_web::{web, App, HttpResponse, HttpServer};

mod shadow;

async fn shared() -> HttpResponse {
    HttpResponse::Ok().finish()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().route("/local", web::post().to(shared)))
        .bind("127.0.0.1:8080")?
        .run()
        .await
}
