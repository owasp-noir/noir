// Tide: multiple verbs chained on one `.at()` binding, `serve_dir`/
// `serve_file` static mounts, `.nest("/api", subapp)` prefix composition,
// and `#[cfg(test)]` gating.
use tide::Request;

async fn idx(_: Request<()>) -> tide::Result<String> { Ok("x".into()) }
async fn upload(_: Request<()>) -> tide::Result<String> { Ok("x".into()) }
async fn download(_: Request<()>) -> tide::Result<String> { Ok("x".into()) }
async fn hello(_: Request<()>) -> tide::Result<String> { Ok("x".into()) }

#[async_std::main]
async fn main() -> tide::Result<()> {
    let mut app = tide::new();
    app.at("/").get(idx);
    app.at("/:file").put(upload).get(download);
    app.at("/assets/*").serve_dir("public/")?;
    app.at("/favicon.ico").serve_file("static/favicon.ico")?;
    app.at("/api").nest({
        let mut api = tide::new();
        api.at("/hello").get(hello);
        api
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    fn t() {
        let mut app = tide::new();
        app.at("/should-not-appear").get(super::idx);
    }
}
