use tide::Request;

async fn h(_req: Request<()>) -> tide::Result { Ok("ok".into()) }

#[async_std::main]
async fn main() -> tide::Result<()> {
    // https://docs.rs/tide/latest/tide/struct.Route.html#method.nest
    let mut api = tide::new();
    api.at("/hello").get(h);
    api.at("/goodbye").post(h);

    let mut app = tide::new();
    app.at("/health").get(h);
    app.at("/api").nest(api);
    app.listen("127.0.0.1:8080").await?;
    Ok(())
}
