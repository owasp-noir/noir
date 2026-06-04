// Gotham verb coverage: typed-extractor pipeline between verb and `.to`,
// the `get_or_head` convenience verb, the multi-method `request(vec![..])`
// form, static `to_file`/`to_dir` terminals, and `associate` closures.
use gotham::hyper::Method;
use gotham::router::builder::*;
use gotham::router::Router;

fn greet_user() {}
fn list_products() {}
fn home() {}
fn create_address() {}
fn get_address() {}

fn router() -> Router {
    build_simple_router(|route| {
        route
            .get("/user/:id")
            .with_path_extractor::<()>()
            .to(greet_user);
        route.get_or_head("/products").to(list_products);
        route.request(vec![Method::GET, Method::HEAD], "/home").to(home);
        route.get("/doc").to_file("assets/doc.html");
        route.associate("/address", |assoc| {
            assoc.post().to(create_address);
            assoc.get().to(get_address);
        });
    })
}

fn main() {}
