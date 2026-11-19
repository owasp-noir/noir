use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use serde::Deserialize;

#[derive(Deserialize)]
struct NewUser { name: String }

async fn list_users() -> impl Responder { HttpResponse::Ok() }
async fn create_user(body: web::Json<NewUser>) -> impl Responder { HttpResponse::Ok() }
async fn get_user(id: web::Path<u64>) -> impl Responder { HttpResponse::Ok() }
async fn delete_user(id: web::Path<u64>) -> impl Responder { HttpResponse::Ok() }
async fn any_method() -> impl Responder { HttpResponse::Ok() }

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            // actix-web >= 4.4: Resource::{get, post, put, patch, delete, head, trace}
            .service(web::resource("/users").get(list_users).post(create_user))
            .service(
                web::scope("/api").service(
                    web::resource("/users/{id}").get(get_user).delete(delete_user),
                ),
            )
            // web::to(): a route with no method guard
            .route("/hook", web::to(any_method))
            // multi-pattern resource
            .service(web::resource(["/v1/ping", "/v2/ping"]).route(web::get().to(any_method)))
            // control: the long form
            .service(web::resource("/control").route(web::get().to(list_users)))
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
