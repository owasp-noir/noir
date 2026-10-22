use serde::Deserialize;
use tide::Request;

#[derive(Deserialize)]
struct Animal {
    name: String,
    legs: u8,
}

#[derive(Deserialize)]
struct Page {
    page: u32,
}

#[async_std::main]
async fn main() -> tide::Result<()> {
    let mut app = tide::new();
    app.at("/orders/shoes").post(order_shoes);
    app.at("/users/:id").get(get_user).delete(get_user);
    let mut api = app.at("/api");
    api.at("/items").get(list_items);
    api.at("/items/:item_id").put(get_user);
    app.at("/static").serve_dir("public/")?;
    app.listen("127.0.0.1:8080").await?;
    Ok(())
}

async fn order_shoes(mut req: Request<()>) -> tide::Result {
    let Animal { name, legs } = req.body_json().await?;
    Ok(format!("Hello, {}! I've put in an order for {} shoes", name, legs).into())
}

async fn get_user(req: Request<()>) -> tide::Result {
    let id = req.param("id")?;
    let tok = req.header("X-Token");
    Ok(id.to_string().into())
}

async fn list_items(req: Request<()>) -> tide::Result {
    let p: Page = req.query()?;
    Ok("".into())
}
