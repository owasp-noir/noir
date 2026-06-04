// The verb-less `web::resource("/p").to(handler)` form: a resource whose
// handler answers any method, registered without an inner `.route(verb())`.
// Emitted as a single GET, with the enclosing scope prefix composed in and
// `.wrap(...)` decorators between `resource()` and `.to()` tolerated.
use actix_web::{web, App, HttpResponse, HttpServer};

async fn index() -> HttpResponse {
    HttpResponse::Ok().finish()
}

async fn health() -> HttpResponse {
    HttpResponse::Ok().finish()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(web::resource("/").to(index)) // GET /
            .service(web::resource("/health").to(health)) // GET /health
            .service(
                web::scope("/api").service(web::resource("/ping").to(index)), // GET /api/ping
            )
            .service(web::resource("/inline").to(|| async { "hi" })) // GET /inline (closure)
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
