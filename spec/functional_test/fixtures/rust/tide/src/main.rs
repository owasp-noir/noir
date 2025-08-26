use tide::prelude::*;
use tide::{Request, Result};

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