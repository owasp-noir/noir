use axum::{
    http::{header, header::AUTHORIZATION, HeaderMap},
    routing::get,
    Router,
};

const SECRET_NAME: &str = "x-secret";

async fn literal(headers: HeaderMap) -> &'static str {
    let _a = headers.get("x-api-key");
    "ok"
}

async fn consts(headers: HeaderMap) -> &'static str {
    let _a = headers.get(AUTHORIZATION);
    let _b = headers.get(header::USER_AGENT);
    let _c = headers.get(axum::http::header::IF_NONE_MATCH);
    // A const of this crate, not an `http::header` name.
    let _d = headers.get(SECRET_NAME);
    "ok"
}

fn app() -> Router {
    Router::new()
        .route("/literal", get(literal))
        .route("/consts", get(consts))
}
