// RWF sub-engine mounting: `engine!("/admin" => engine)` is a mount, not
// an endpoint, and its child routes inherit the `/admin` prefix.
use rwf::http::{Engine, Server};
use rwf::prelude::*;

struct Home;
struct Index;
struct About;

#[tokio::main]
async fn main() {
    let engine = Engine::new(vec![
        route!("/index" => Index),
        route!("/about" => About),
    ]);

    Server::new(vec![
        route!("/" => Home),
        engine!("/admin" => engine),
    ])
    .launch()
    .await
    .unwrap();
}
