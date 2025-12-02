use gotham::router::builder::*;
use gotham::router::Router;
use gotham::state::State;
use hyper::{Body, Response, StatusCode};
use hyper::header;

fn hello_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("Hello, Gotham!".into())
        .unwrap();
    (state, res)
}

fn user_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("User endpoint".into())
        .unwrap();
    (state, res)
}

fn create_user_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::CREATED)
        .body("User created".into())
        .unwrap();
    (state, res)
}

fn update_product_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("Product updated".into())
        .unwrap();
    (state, res)
}

fn delete_item_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::NO_CONTENT)
        .body("".into())
        .unwrap();
    (state, res)
}

fn search_handler(state: State) -> (State, Response<Body>) {
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("Search results".into())
        .unwrap();
    (state, res)
}

fn session_handler(state: State) -> (State, Response<Body>) {
    // Cookie access pattern
    let session_id = state.cookie("session_id");
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("Session info".into())
        .unwrap();
    (state, res)
}

fn auth_handler(state: State) -> (State, Response<Body>) {
    // Header access pattern
    let auth = state.headers().get("Authorization");
    let api_key = state.headers().get("X-API-Key");
    let res = Response::builder()
        .status(StatusCode::OK)
        .body("Auth info".into())
        .unwrap();
    (state, res)
}

fn router() -> Router {
    Router::builder()
        .get("/")
        .to(hello_handler)
        .get("/users/:id")
        .to(user_handler)
        .post("/users")
        .to(create_user_handler)
        .put("/api/products/:id")
        .to(update_product_handler)
        .delete("/api/items/:id")
        .to(delete_item_handler)
        .get("/search")
        .to(search_handler)
        .patch("/api/profiles/:id")
        .to(update_product_handler)
        .head("/api/health")
        .to(hello_handler)
        .options("/api/config")
        .to(hello_handler)
        .get("/session")
        .to(session_handler)
        .get("/auth")
        .to(auth_handler)
        .build()
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let addr = "127.0.0.1:3000";
    println!("Listening for requests at http://{}", addr);
    gotham::start(addr, router()).await
}