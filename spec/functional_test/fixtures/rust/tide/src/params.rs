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

// Query parameters test
async fn search(req: Request<()>) -> Result {
    let query: SearchQuery = req.query()?;
    Ok(format!("Search: {}", query.q).into())
}

// JSON body test
async fn create_user(mut req: Request<()>) -> Result {
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
