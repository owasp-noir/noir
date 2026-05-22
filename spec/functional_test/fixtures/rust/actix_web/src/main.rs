use actix_web::{get, post, put, delete, web, HttpRequest, HttpResponse, HttpServer, Responder};
use serde::Deserialize;

#[derive(Deserialize)]
struct UserInfo {
    id: u32,
}

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
    page: Option<u32>,
}

#[derive(Deserialize)]
struct LoginForm {
    username: String,
    password: String,
}

// Basic endpoints
#[get("/")]
async fn hello() -> impl Responder {
    HttpResponse::Ok().body("Hello world!")
}

#[post("/echo")]
async fn echo(req_body: String) -> impl Responder {
    HttpResponse::Ok().body(req_body)
}

// Path parameter extraction
#[get("/users/{id}")]
async fn get_user(path: web::Path<u32>) -> impl Responder {
    HttpResponse::Ok().body(format!("User {}", path.into_inner()))
}

#[get("/users/{user_id}/posts/{post_id}")]
async fn get_user_post(path: web::Path<(u32, u32)>) -> impl Responder {
    let (user_id, post_id) = path.into_inner();
    HttpResponse::Ok().body(format!("User {} Post {}", user_id, post_id))
}

// Query parameter extraction
#[get("/search")]
async fn search(query: web::Query<SearchQuery>) -> impl Responder {
    HttpResponse::Ok().body(format!("Searching for: {}", query.q))
}

// JSON body extraction
#[post("/api/users")]
async fn create_user(body: web::Json<UserInfo>) -> impl Responder {
    HttpResponse::Ok().body(format!("Created user {}", body.id))
}

// Form body extraction
#[post("/login")]
async fn login(form: web::Form<LoginForm>) -> impl Responder {
    HttpResponse::Ok().body(format!("Login: {}", form.username))
}

// Header extraction
#[get("/protected")]
async fn protected(req: HttpRequest) -> impl Responder {
    let auth = req.headers().get("Authorization");
    HttpResponse::Ok().body("Protected")
}

// Cookie extraction
#[get("/session")]
async fn session(req: HttpRequest) -> impl Responder {
    let session_id = req.cookie("session_id");
    HttpResponse::Ok().body("Session")
}

// Mixed parameters
#[put("/articles/{id}")]
async fn update_article(
    path: web::Path<u32>,
    body: web::Json<UserInfo>,
    req: HttpRequest,
) -> impl Responder {
    let token = req.headers().get("X-API-Token");
    HttpResponse::Ok().body("Updated")
}

// Scoped service registration. In real actix-web apps, handlers are
// often declared with route attributes and mounted under web::scope(...)
// from configure functions.
#[get("/posts")]
async fn scoped_posts() -> impl Responder {
    HttpResponse::Ok().body("Scoped posts")
}

#[get("/reports/{id}")]
async fn scoped_report(path: web::Path<u32>) -> impl Responder {
    HttpResponse::Ok().body(format!("Report {}", path.into_inner()))
}

#[get("/nested")]
async fn nested_scoped_posts() -> impl Responder {
    HttpResponse::Ok().body("Nested scoped posts")
}

fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api")
            .service(scoped_posts)
            .service(scoped_report),
    );
    cfg.service(
        web::scope("/root")
            .service(web::scope("/api").service(nested_scoped_posts)),
    );
}

async fn manual_hello() -> impl Responder {
    HttpResponse::Ok().body("Hey there!")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[get("/should-not-appear-attr")]
    async fn test_attr_route() -> impl Responder {
        HttpResponse::Ok().finish()
    }

    async fn test_manual() -> impl Responder {
        HttpResponse::Ok().finish()
    }

    fn test_app() {
        let _app = actix_web::App::new()
            .route("/should-not-appear-builder", web::get().to(test_manual));
    }
}
