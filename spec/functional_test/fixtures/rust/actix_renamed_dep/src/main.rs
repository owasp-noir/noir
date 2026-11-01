use web::{get, App, HttpResponse, HttpServer};

#[get("/hello")]
async fn hello() -> HttpResponse {
    HttpResponse::Ok().finish()
}

fn main() {
    HttpServer::new(|| App::new().service(hello));
}
