use actix_web::{web, App, HttpServer, HttpResponse, get, post};
use actix_web::middleware::DefaultHeaders;
use actix_cors::Cors;
use actix_governor::{Governor, GovernorConfigBuilder};

// Public endpoint, only covered by app-wide middleware.
#[get("/health")]
async fn health() -> HttpResponse {
    HttpResponse::Ok().body("ok")
}

#[get("/api/users")]
async fn list_users() -> HttpResponse {
    HttpResponse::Ok().body("users")
}

// Lives under the rate-limited /admin scope.
#[post("/admin/import")]
async fn admin_import(body: String) -> HttpResponse {
    HttpResponse::Ok().body("imported")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let governor_conf = GovernorConfigBuilder::default().finish().unwrap();

    HttpServer::new(move || {
        App::new()
            .wrap(Cors::permissive())
            .wrap(
                DefaultHeaders::new()
                    .add(("X-Frame-Options", "DENY"))
                    .add(("Content-Security-Policy", "default-src 'self'")),
            )
            .app_data(web::JsonConfig::default().limit(4096))
            .service(health)
            .service(list_users)
            .service(
                web::scope("/admin")
                    .wrap(Governor::new(&governor_conf))
                    .service(admin_import),
            )
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test-only app: a permissive CORS here must NOT leak onto the real
    // endpoints above.
    fn build_test_app() {
        let _app = App::new()
            .wrap(Cors::permissive())
            .app_data(web::PayloadConfig::new(usize::MAX));
    }
}
