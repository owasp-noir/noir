use actix_web::{web, App, HttpResponse, HttpServer};

mod api;
mod handlers;
mod mock;
mod models;
#[path = "other/real_impl.rs"]
mod pathmod;

#[cfg(not(test))]
use crate::handlers::list_items;
#[cfg(test)]
use crate::mock::list_items;
use crate::handlers::show_item;
use api::v1::{self as v};

#[derive(serde::Deserialize)]
pub struct Paging {
    pub cursor: String,
}

struct State;

impl State {
    fn show_item(&self) -> HttpResponse {
        HttpResponse::Ok().finish()
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/items", web::get().to(list_items))
            .route("/item", web::get().to(show_item))
            .route("/alias", web::get().to(v::show))
            .route("/path", web::get().to(pathmod::real))
            .route("/cyc", web::get().to(api::v1::missing))
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
