use actix_web::{get, post, web, HttpRequest, HttpResponse, Responder};
use serde::Deserialize;

#[derive(Deserialize)]
struct UserInfo {
    id: u32,
}

#[get("/")]
async fn hello() -> impl Responder {
    let status = HealthCheck::ready().await;
    HttpResponse::Ok().body(render_home(status))
}

#[get("/users/{id}")]
async fn get_user(path: web::Path<u32>) -> impl Responder {
    let user = UserService::load(path.into_inner()).await;
    AuditLog::read_user();
    HttpResponse::Ok().json(UserPresenter::render(user))
}

#[post("/api/users")]
async fn create_user(body: web::Json<UserInfo>) -> impl Responder {
    let user = UserService::create(body.into_inner()).await;
    AuditLog::write(&user);
    HttpResponse::Created().json(UserPresenter::render(user))
}

#[get("/protected")]
#[allow(dead_code)]
#[allow(unused_variables)]
async fn protected(req: HttpRequest) -> impl Responder {
    let marker = "DangerService::run()";
    // Ignored::call();
    let auth = req.headers().get("Authorization");
    AuthService::validate(auth);
    HttpResponse::Ok().body(marker)
}
