// Builder-style actix-web routing with a glob import, exercising bare
// verb/scope/resource identifiers and nested scope prefix composition —
// the shape real apps (e.g. Lemmy) use via `use actix_web::web::*`.
use actix_web::web::*;
use actix_web::{App, HttpResponse, HttpServer, Responder};

async fn get_site() -> impl Responder { HttpResponse::Ok().finish() }
async fn create_site() -> impl Responder { HttpResponse::Ok().finish() }
async fn search() -> impl Responder { HttpResponse::Ok().finish() }
async fn list_communities() -> impl Responder { HttpResponse::Ok().finish() }
async fn approve_follow() -> impl Responder { HttpResponse::Ok().finish() }

fn config(cfg: &mut ServiceConfig) {
    cfg.service(
        scope("/api/v4")
            .service(
                scope("/site")
                    .route("", get().to(get_site))
                    .route("", post().to(create_site)),
            )
            .service(resource("/search").route(get().to(search)))
            .service(
                scope("/community")
                    .route("", get().to(list_communities))
                    .service(
                        scope("/pending")
                            .route("/approve", post().to(approve_follow)),
                    ),
            ),
    );
}

// Generic multi-method attribute macro.
#[actix_web::route("/multi", method = "GET", method = "POST")]
async fn multi_handler() -> impl Responder {
    HttpResponse::Ok().finish()
}

// Regex-constrained path param normalises to the bare name.
#[actix_web::get("/page-{id:\\d+}")]
async fn page_handler() -> impl Responder {
    HttpResponse::Ok().finish()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().configure(config).service(multi_handler).service(page_handler))
        .bind(("127.0.0.1", 8080))?
        .run()
        .await
}

#[cfg(test)]
mod tests {
    use super::*;
    fn test_app() {
        let _app = App::new().route("/should-not-appear", get().to(get_site));
    }
}
