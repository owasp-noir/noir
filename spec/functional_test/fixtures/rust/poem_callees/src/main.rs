use poem::listener::TcpListener;
use poem::web::{Json, Path};
use poem::{get, handler, post, Route, Server};

#[handler]
async fn hello() -> String {
    let status = HealthCheck::ready();
    render_home(status)
}

#[handler]
async fn get_user(Path(id): Path<u64>, req: &poem::Request) -> String {
    let token = req.header("X-Token").unwrap_or_default();
    let session = req.cookie().get("session_id");
    let user = UserService::load(id);
    AuditLog::read_user(&token, session);
    UserPresenter::render(user)
}

#[handler]
async fn create_user(Json(body): Json<serde_json::Value>) -> String {
    let user = UserService::create(body);
    UserPresenter::render(user)
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let app = Route::new()
        .at("/hello", get(hello))
        .at("/users/:id", get(get_user))
        .at("/users", post(create_user));

    Server::new(TcpListener::bind("127.0.0.1:3000"))
        .run(app)
        .await
}
