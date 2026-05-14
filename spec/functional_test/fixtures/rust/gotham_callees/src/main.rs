use gotham::router::builder::*;
use gotham::router::Router;
use gotham::state::State;
use hyper::{Body, Response, StatusCode};

fn home_handler(state: State) -> (State, Response<Body>) {
    let status = HealthCheck::ready();
    let body = render_home(status);
    respond(state, body, StatusCode::OK)
}

fn user_handler(state: State) -> (State, Response<Body>) {
    let user = UserService::load();
    AuditLog::read_user();
    let body = UserPresenter::render(user);
    respond(state, body, StatusCode::OK)
}

fn create_user_handler(state: State) -> (State, Response<Body>) {
    let user = UserService::create();
    AuditLog::write();
    let body = UserPresenter::render(user);
    respond(state, body, StatusCode::CREATED)
}

fn session_handler(state: State) -> (State, Response<Body>) {
    let session_id = /* state.cookie("debug_session") */ state.cookie("session_id");
    AuthService::session(session_id);
    respond(state, "session".to_string(), StatusCode::OK)
}

fn auth_handler(state: State) -> (State, Response<Body>) {
    let auth = /* state.headers().get("X-Debug") */ state.headers().get("Authorization");
    let api_key = state.headers().get("X-API-Key");
    AuthService::validate(auth, api_key);
    respond(state, "auth".to_string(), StatusCode::OK)
}

fn respond(state: State, body: String, status: StatusCode) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(status)
        .body(body.into())
        .unwrap();
    (state, res)
}

fn router() -> Router {
    Router::builder()
        .get("/")
        .to(home_handler)
        .get("/users/:id")
        .to(user_handler)
        .post("/users")
        .to(create_user_handler)
        .get("/session")
        .to(session_handler)
        .get("/auth")
        .to(auth_handler)
        .build()
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    gotham::start("127.0.0.1:3000", router()).await
}
