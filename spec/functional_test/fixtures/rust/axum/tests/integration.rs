// Regression guard: anything under `tests/` is a Rust integration
// test binary (`cargo test --test integration`), never a production
// endpoint. None of the URLs below should appear in the fixture's
// expected-endpoints list.
use axum::{routing::get, Router};

#[tokio::test]
async fn integration_routes() {
    let _app: Router = Router::new()
        .route("/should-not-appear-integration", get(|| async { "ok" }));
}
