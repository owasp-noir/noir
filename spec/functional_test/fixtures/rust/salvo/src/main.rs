use salvo::prelude::*;

#[handler]
async fn hello() -> &'static str {
    "Hello, World!"
}

#[handler]
async fn get_user(req: &mut Request) -> String {
    let id = req.param::<String>("id").unwrap();
    let token = req.header("X-Token").unwrap_or_default();
    let session = req.cookie("session_id").unwrap_or_default();
    format!("User: {}", id)
}

#[handler]
async fn create_user(req: &mut Request) -> &'static str {
    let body: JsonBody<serde_json::Value> = req.extract().await.unwrap();
    "Created"
}

#[handler]
async fn search(req: &mut Request) -> &'static str {
    let query: QueryParam = req.extract().await.unwrap();
    "Results"
}

#[handler]
async fn update_item(req: &mut Request) -> &'static str {
    let form: FormBody<serde_json::Value> = req.extract().await.unwrap();
    "Updated"
}

#[tokio::main]
async fn main() {
    let router = Router::new()
        .push(Router::with_path("hello").get(hello))
        .push(Router::with_path("users/<id>").get(get_user))
        .push(Router::with_path("users").post(create_user))
        .push(Router::with_path("search").get(search))
        .push(Router::with_path("items/<id>").put(update_item));

    let acceptor = TcpListener::new("127.0.0.1:5800").bind().await;
    Server::new(acceptor).serve(router).await;
}
