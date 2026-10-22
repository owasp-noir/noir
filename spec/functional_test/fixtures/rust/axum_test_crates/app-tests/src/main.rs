use axum::{routing::get, Router};

#[tokio::main]
async fn main() {
    let app = Router::new().route("/in-app-tests", get(handler));
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3001").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn handler() -> &'static str {
    "test app"
}
