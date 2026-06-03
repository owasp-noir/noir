use axum::{routing::get, routing::post, Router};
use axum::extract::DefaultBodyLimit;
use tower_http::cors::CorsLayer;
use tower_http::set_header::SetResponseHeaderLayer;
use tower_governor::GovernorLayer;
use http::header;

async fn health() -> &'static str {
    "ok"
}

async fn upload() -> &'static str {
    "uploaded"
}

fn app() -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/upload", post(upload))
        // Wide-open CORS: any origin accepted.
        .layer(CorsLayer::very_permissive())
        // Rate limiting via tower_governor.
        .layer(GovernorLayer::default())
        // HSTS hardening header.
        .layer(SetResponseHeaderLayer::overriding(
            header::STRICT_TRANSPORT_SECURITY,
            "max-age=31536000",
        ))
        // Body size limit removed entirely — DoS risk.
        .layer(DefaultBodyLimit::disable())
}
