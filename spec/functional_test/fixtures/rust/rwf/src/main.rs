use rwf::prelude::*;
use rwf::http::Server;

#[derive(Default)]
struct IndexController;

#[async_trait]
impl Controller for IndexController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        Ok(Response::new().html("<h1>Hello, World!</h1>"))
    }
}

#[derive(Default)]
struct UserController;

#[async_trait]
impl Controller for UserController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        match request.method() {
            Method::GET => Ok(Response::new().json(&serde_json::json!({"users": []}))),
            Method::POST => Ok(Response::new().json(&serde_json::json!({"message": "User created"}))),
            _ => Ok(Response::new().status(405).text("Method not allowed"))
        }
    }
}

#[derive(Default)]
struct ApiController;

#[async_trait] 
impl Controller for ApiController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        Ok(Response::new().json(&serde_json::json!({"api": "v1"})))
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    Server::new(vec![
        route!("/" => IndexController),
        route!("/users" => UserController),
        route!("/api" => ApiController),
    ])
    .launch("0.0.0.0:8000")
    .await
}