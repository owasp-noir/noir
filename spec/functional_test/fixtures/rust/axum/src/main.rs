use axum::{response::Html, routing::get, Router};

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(handler))
        .route("/foo", get(handler))
        .route("/bar", post(handler))
        .nest(
            "/api",
            Router::new()
                .route("/users", get(handler))
                .route("/admin", post(handler)),
        );
        
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();
    println!("listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

async fn handler() -> Html<&'static str> {
    Html("<h1>Hello, World!</h1>")
}

// Regression guard: routes registered inside `#[cfg(test)] mod tests`
// are unit-test fixtures, not production endpoints. None of the URLs
// below should appear in the fixture's expected-endpoints list.
#[cfg(test)]
mod tests {
    use super::*;
    use axum::routing::post;

    #[tokio::test]
    async fn test_app_routes() {
        let _app = Router::new()
            .route("/should-not-appear-get", get(handler))
            .route("/should-not-appear-post", post(handler));
    }
}
