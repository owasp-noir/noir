use tide::Request;

async fn show(_req: Request<()>) -> tide::Result<String> {
    Ok("ok".to_string())
}

#[async_std::main]
async fn main() -> tide::Result<()> {
    let mut app = tide::new();

    // tree-sitter-rust splits a string literal at every escape, so a route
    // whose path carries one used to be truncated at the first escape.
    app.at("/page-{id:\\d+}").get(show);
    app.at("/file-{name:.*\\.json}").get(show);

    // Unescaped neighbours: these were always read correctly, and must stay
    // that way.
    app.at("/plain/{name}").get(show);

    app.listen("127.0.0.1:8080").await?;
    Ok(())
}
