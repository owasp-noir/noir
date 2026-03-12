use actix_web::{web, App, HttpServer, HttpRequest, HttpResponse, get, post};
use actix_web_httpauth::middleware::HttpAuthentication;
use actix_web_httpauth::extractors::bearer::BearerAuth;

// Public endpoint - no auth
#[get("/health")]
async fn health() -> HttpResponse {
    HttpResponse::Ok().body("ok")
}

// Public endpoint
#[get("/public")]
async fn public_page() -> HttpResponse {
    HttpResponse::Ok().body("public content")
}

// Protected by BearerAuth extractor
#[get("/profile")]
async fn profile(auth: BearerAuth) -> HttpResponse {
    HttpResponse::Ok().body(format!("User: {}", auth.token()))
}

// Protected by custom auth guard
#[guard = "AdminGuard"]
#[get("/admin/users")]
async fn admin_users() -> HttpResponse {
    HttpResponse::Ok().body("admin users list")
}

// Protected by AuthUser request guard in signature
#[post("/api/posts")]
async fn create_post(user: AuthUser, body: web::Json<PostData>) -> HttpResponse {
    HttpResponse::Ok().body("created")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(health)
            .service(public_page)
            .service(profile)
            .service(admin_users)
            .service(
                web::scope("/api")
                    .wrap(HttpAuthentication::bearer(validator))
                    .service(create_post)
            )
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}

struct AuthUser {
    id: u64,
    name: String,
}

struct PostData {
    title: String,
    content: String,
}

struct AdminGuard;

async fn validator(
    req: actix_web::dev::ServiceRequest,
    credentials: BearerAuth,
) -> Result<actix_web::dev::ServiceRequest, actix_web::Error> {
    Ok(req)
}
