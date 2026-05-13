use salvo::prelude::*;

#[handler]
async fn hello() -> String {
    let status = HealthCheck::ready();
    render_home(status)
}

#[handler]
async fn get_user(req: &mut Request) -> String {
    let token = req.header("X-Token").unwrap_or_default();
    let session = req.cookie("session_id").unwrap_or_default();
    let user = UserService::load(req.param::<String>("id").unwrap());
    AuditLog::read_user(&token, &session);
    UserPresenter::render(user)
}

#[handler]
async fn create_user(req: &mut Request) -> String {
    let body: JsonBody<serde_json::Value> = req.extract();
    let user = UserService::create(body);
    UserPresenter::render(user)
}

#[endpoint(method = Post, path = "/api/submit/<id>")]
#[handler]
async fn submit_form(req: &mut Request) -> &'static str {
    let form: FormBody<serde_json::Value> = req.extract();
    let auth = req.header("Authorization").unwrap_or_default();
    SubmitService::save(form, auth);
    "Submitted"
}

#[tokio::main]
async fn main() {
    let router = Router::new()
        .push(Router::with_path("hello").get(hello))
        .push(Router::with_path("users/<id>").get(get_user))
        .push(Router::with_path("users").post(create_user));

    let acceptor = TcpListener::new("127.0.0.1:5800").bind().await;
    Server::new(acceptor).serve(router).await;
}
