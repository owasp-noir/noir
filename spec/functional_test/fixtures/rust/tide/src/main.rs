use tide::prelude::*;
use tide::{Request, Result};

#[derive(Debug, Deserialize)]
struct SearchQuery {
    q: String,
    limit: Option<i32>,
}

#[derive(Debug, Deserialize)]
struct UserData {
    name: String,
    email: String,
}

#[derive(Debug, Deserialize)]
struct LoginForm {
    username: String,
    password: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let mut app = tide::new();

    // GET /
    app.at("/").get(|_| async { Ok("Hello, World!") });

    // GET /hello
    app.at("/hello").get(|_| async { Ok("Hello!") });

    // GET /users/:id
    app.at("/users/:id").get(get_user);

    // POST /users
    app.at("/users").post(create_user);

    // PUT /users/:id
    app.at("/users/:id").put(update_user);

    // DELETE /users/:id
    app.at("/users/:id").delete(delete_user);

    // GET /products/:category/:id
    app.at("/products/:category/:id").get(get_product);

    // Alternative syntax - route variable assignment
    let health_route = app.at("/health");
    health_route.get(health_check);

    let api_route = app.at("/api/v1/status");
    api_route.get(api_status);

    // Query parameters
    app.at("/search").get(search);

    // JSON body
    app.at("/api/users").post(create_user_json);

    // Form body
    app.at("/login").post(login);

    // Headers
    app.at("/auth").get(auth_handler);

    // Cookies
    app.at("/session").get(session_handler);

    // Multiple parameters
    app.at("/complex/:id").post(complex_handler);

    app.listen("127.0.0.1:8080").await?;
    Ok(())
}

async fn get_user(req: Request<()>) -> Result {
    let id = req.param("id")?;
    Ok(format!("User ID: {}", id).into())
}

async fn create_user(_req: Request<()>) -> Result {
    Ok("User created".into())
}

async fn update_user(req: Request<()>) -> Result {
    let id = req.param("id")?;
    Ok(format!("User {} updated", id).into())
}

async fn delete_user(req: Request<()>) -> Result {
    let id = req.param("id")?;
    Ok(format!("User {} deleted", id).into())
}

async fn get_product(req: Request<()>) -> Result {
    let category = req.param("category")?;
    let id = req.param("id")?;
    Ok(format!("Product: {} in category {}", id, category).into())
}

async fn health_check(_req: Request<()>) -> Result {
    Ok("OK".into())
}

async fn api_status(_req: Request<()>) -> Result {
    Ok("API is running".into())
}

// Query parameters test
async fn search(req: Request<()>) -> Result {
    let query: SearchQuery = req.query()?;
    Ok(format!("Search: {}", query.q).into())
}

// JSON body test
async fn create_user_json(mut req: Request<()>) -> Result {
    let user: UserData = req.body_json().await?;
    Ok(format!("Created user: {}", user.name).into())
}

// Form body test
async fn login(mut req: Request<()>) -> Result {
    let form: LoginForm = req.body_form().await?;
    Ok(format!("Logged in: {}", form.username).into())
}

// Header test
async fn auth_handler(req: Request<()>) -> Result {
    let token = req.header("Authorization");
    let api_key = req.header("X-API-Key");
    Ok("Authenticated".into())
}

// Cookie test
async fn session_handler(req: Request<()>) -> Result {
    let session = req.cookie("session_id");
    Ok("Session validated".into())
}

// Multiple parameters test
async fn complex_handler(mut req: Request<()>) -> Result {
    let id = req.param("id")?;
    let query: SearchQuery = req.query()?;
    let user: UserData = req.body_json().await?;
    let token = req.header("Authorization");
    let session = req.cookie("session_id");
    Ok("Complex operation".into())
}