use axum::{routing::get, Router};

// The one real route. The workspace test crates next to it (app-tests,
// tests-fuzz, playwright-tests, e2e_test) are harnesses, not the app.
#[tokio::main]
async fn main() {
    let app = Router::new().route("/real", get(handler));
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn handler() -> &'static str {
    "real"
}
