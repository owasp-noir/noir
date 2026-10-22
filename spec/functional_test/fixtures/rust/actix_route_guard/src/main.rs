use actix_web::{guard, http::Method, web, App, HttpResponse, HttpServer};

async fn index() -> HttpResponse { HttpResponse::Ok().finish() }

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(web::resource("/path").route(web::route().guard(guard::Get()).to(index)))
            .route("/a", web::route().guard(guard::Post()).to(index))
            .route("/b", web::method(Method::PATCH).to(index))
            .route("/c", web::route().to(index))
            .service(web::resource("/d").guard(guard::Header("content-type", "text/plain")).to(index))
            .default_service(web::to(index))
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
