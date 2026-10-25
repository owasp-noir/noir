use actix_web::{web, App, HttpServer};
use my_api::{
    items,
    posts::{create::create_post, read::get_post as read_post},
};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().service(
            web::scope("/api")
                .route("/post", web::post().to(create_post))
                .route("/post", web::get().to(read_post))
                .route("/items", web::get().to(items::list)),
        )
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
