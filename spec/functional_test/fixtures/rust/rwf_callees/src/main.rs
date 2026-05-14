use rwf::http::Server;
use rwf::prelude::*;

#[derive(Default)]
struct UsersController;

#[async_trait]
impl Controller for UsersController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        match request.method() {
            Method::GET => {
                let users = UserService::list();
                AuditLog::list_users();
                Ok(Response::new().json(&UserPresenter::render(users)))
            }
            Method::POST => {
                let body = request.body()?;
                let user = UserService::create(body);
                AuditLog::write();
                Ok(Response::new().json(&UserPresenter::render(user)))
            }
            _ => Ok(Response::new().status(405).text("Method not allowed")),
        }
    }
}

#[derive(Default)]
struct UserController;

#[async_trait]
impl Controller for UserController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let id = request.path_parameter("id")?;
        let auth = /* request.header("X-Debug") */ request.header("Authorization");
        let user = UserService::load(id, auth);
        AuditLog::read_user();
        Ok(Response::new().json(&UserPresenter::render(user)))
    }
}

#[derive(Default)]
struct SessionController;

#[async_trait]
impl Controller for SessionController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let session = request.cookie("session_id");
        let query = request.query_parameter("redirect");
        AuthService::session(session, query);
        Ok(Response::new().text("OK"))
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    Server::new(vec![
        route!("/users" => UsersController),
        route!("/users/:id" => UserController),
        route!("/session" => SessionController),
    ])
    .launch("0.0.0.0:8000")
    .await
}
