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

// Path parameters - /users/:id
#[derive(Default)]
struct UserIdController;

#[async_trait]
impl Controller for UserIdController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let id = request.path_parameter::<i64>("id")?;
        Ok(Response::new().json(&serde_json::json!({"user_id": id})))
    }
}

// Query parameters - /search?q=term&limit=10
#[derive(Default)]
struct SearchController;

#[async_trait]
impl Controller for SearchController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let query = request.query_parameter("q");
        let limit = request.query_parameter("limit");
        Ok(Response::new().json(&serde_json::json!({"query": query, "limit": limit})))
    }
}

// Body/JSON parameters
#[derive(Default)]
struct CreateController;

#[async_trait]
impl Controller for CreateController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let body = request.body()?;
        Ok(Response::new().json(&serde_json::json!({"created": true})))
    }
}

// Form data parameters
#[derive(Default)]
struct FormController;

#[async_trait]
impl Controller for FormController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let form = request.form_data()?;
        Ok(Response::new().text("Form submitted"))
    }
}

// Headers
#[derive(Default)]
struct AuthController;

#[async_trait]
impl Controller for AuthController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let auth = request.header("Authorization");
        let api_key = request.header("X-API-Key");
        Ok(Response::new().text("OK"))
    }
}

// Cookies
#[derive(Default)]
struct SessionController;

#[async_trait]
impl Controller for SessionController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let session = request.cookie("session_id");
        Ok(Response::new().text("OK"))
    }
}

// Multiple path parameters - /posts/:category/:id
#[derive(Default)]
struct PostController;

#[async_trait]
impl Controller for PostController {
    async fn handle(&self, request: &Request) -> Result<Response, Error> {
        let category = request.path_parameter::<String>("category")?;
        let id = request.path_parameter::<i64>("id")?;
        Ok(Response::new().json(&serde_json::json!({"category": category, "id": id})))
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    Server::new(vec![
        route!("/" => IndexController),
        route!("/users" => UserController),
        route!("/api" => ApiController),
        route!("/users/:id" => UserIdController),
        route!("/search" => SearchController),
        route!("/create" => CreateController),
        route!("/form" => FormController),
        route!("/auth" => AuthController),
        route!("/session" => SessionController),
        route!("/posts/:category/:id" => PostController),
    ])
    .launch("0.0.0.0:8000")
    .await
}