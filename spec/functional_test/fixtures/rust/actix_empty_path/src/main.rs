use actix_web::{get, post, route, web, App, HttpResponse, HttpServer, Responder};

#[get("")]
async fn list() -> impl Responder { HttpResponse::Ok() }

#[post("")]
async fn create() -> impl Responder { HttpResponse::Ok() }

#[get("/{id}")]
async fn show(id: web::Path<u64>) -> impl Responder { HttpResponse::Ok() }

#[get("")]
async fn root_empty() -> impl Responder { HttpResponse::Ok() }

#[route("", method = "GET", method = "POST")]
async fn both() -> impl Responder { HttpResponse::Ok() }

#[get("", guard = "my_guard")]
async fn guarded() -> impl Responder { HttpResponse::Ok() }

#[get("", name = "named_route")]
async fn named() -> impl Responder { HttpResponse::Ok() }

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(web::scope("/users").service(list).service(create).service(show))
            .service(web::scope("/a").service(both))
            .service(web::scope("/b").service(guarded))
            .service(web::scope("/c").service(named))
            .service(root_empty)
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
