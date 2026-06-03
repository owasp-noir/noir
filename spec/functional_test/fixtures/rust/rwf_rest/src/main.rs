// RWF route registration beyond the basic `route!` macro: the `crud!`
// / `rest!` REST conventions, the `.route(...)` method form, and a
// scoped controller path. All four sit inside the usual
// `Server::new(vec![ ... ])` macro body.
use rwf::http::Server;
use rwf::macros::{crud, rest, route};
use rwf::prelude::*;

#[derive(Default)]
struct IndexController;

#[async_trait]
impl Controller for IndexController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        Ok(Response::new().html("<h1>home</h1>"))
    }
}

#[derive(Default)]
struct LoginController;

#[async_trait]
impl Controller for LoginController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        match request.method() {
            Method::GET => Ok(Response::new().html("login form")),
            Method::POST => Ok(Response::new().redirect("/")),
            _ => Ok(Response::new().status(405).text("nope")),
        }
    }
}

// ModelController auto-implements the full CRUD surface.
#[derive(Default)]
struct UserController;

#[async_trait]
impl ModelController for UserController {
    type Model = User;
}

// RestController with a couple of explicit actions; the framework still
// registers the whole REST surface.
#[derive(Default)]
struct PostController;

#[async_trait]
impl RestController for PostController {
    type Resource = i64;

    async fn list(&self, _request: &Request) -> Result<Response, Error> {
        Ok(Response::new().json(&serde_json::json!([])))
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    Server::new(vec![
        route!("/login" => LoginController),
        IndexController.route("/"),
        crud!("/api/users" => UserController),
        rest!("/api/posts" => PostController),
        route!("/upload" => controllers::Upload),
    ])
    .launch("0.0.0.0:8000")
    .await
}
