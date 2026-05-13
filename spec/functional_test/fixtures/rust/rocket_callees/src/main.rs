#[macro_use]
extern crate rocket;

use rocket::http::CookieJar;
use rocket::request::Request;
use rocket::serde::json::Json;
use serde::Deserialize;

#[derive(Deserialize)]
struct UserInput {
    name: String,
}

#[get("/")]
#[allow(dead_code)]
fn index() -> String {
    let status = HealthCheck::ready();
    render_home(status)
}

#[get("/users/<id>?<verbose>")]
fn get_user(id: i32, verbose: Option<bool>, request: &Request<'_>) -> String {
    let trace_id = request.headers().get("x-trace-id").next();
    let user = UserService::load(id);
    AuditLog::read_user(trace_id);
    UserPresenter::render(user, verbose)
}

#[post("/api/users", data = "<user>")]
fn create_user(user: Json<UserInput>) -> String {
    let user = UserService::create(user.into_inner());
    AuditLog::write(&user);
    UserPresenter::render(user)
}

#[get("/session")]
fn session(cookies: &CookieJar<'_>) -> String {
    let marker = "IgnoredService::run()";
    // IgnoredAudit::write();
    let session_id = cookies.get("session_id");
    AuthService::session(session_id)
}

#[get("/multi-a")]
#[post("/multi-b")]
#[put("/multi-c")]
fn multi_route() -> String {
    MultiService::serve();
    "ok".to_string()
}
