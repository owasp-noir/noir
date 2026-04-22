use poem::{delete, get, handler, post, put, Route, Server};
use poem::listener::TcpListener;
use poem::web::{Form, Json, Path, Query};

#[handler]
async fn hello() -> &'static str {
    "Hello, World!"
}

#[handler]
async fn get_user(Path(id): Path<u64>, req: &poem::Request) -> String {
    let token = req.header("X-Token").unwrap_or_default();
    let session = req.cookie().get("session_id");
    format!("User: {}", id)
}

#[handler]
async fn create_user(Json(body): Json<serde_json::Value>) -> &'static str {
    "Created"
}

#[handler]
async fn search(Query(params): Query<std::collections::HashMap<String, String>>) -> &'static str {
    "Results"
}

#[handler]
async fn update_item(Path(id): Path<u64>, Form(data): Form<serde_json::Value>) -> &'static str {
    "Updated"
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let app = Route::new()
        .at("/hello", get(hello))
        .at("/users/:id", get(get_user))
        .at("/users", post(create_user))
        .at("/search", get(search))
        .at("/items/:id", put(update_item));

    Server::new(TcpListener::bind("127.0.0.1:3000"))
        .run(app)
        .await
}
