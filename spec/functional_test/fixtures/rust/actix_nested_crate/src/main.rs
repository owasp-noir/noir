use actix_web::{get, App, HttpResponse, HttpServer};

#[get("/real")]
async fn real() -> HttpResponse {
    HttpResponse::Ok().finish()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(real))
        .bind(("127.0.0.1", 8080))?
        .run()
        .await
}
