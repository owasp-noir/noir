use axum::{extract::{Form, Query}, http::HeaderMap, response::Html, routing::{any, get, post}, Router};
use axum_extra::extract::CookieJar;
use tower_http::services::ServeDir;

#[tokio::main]
async fn main() {
    let internal_routes = Router::new().route("/health", get(handler));

    let app = Router::new()
        .route("/", get(handler))
        .route("/foo", get(handler))
        .route("/bar", post(handler))
        .route("/search", get(search))
        .route("/submit", post(submit))
        .route("/headers", get(headers))
        .route("/session", get(session))
        // Verb-agnostic registration — typically used for WebSocket
        // upgrade endpoints. axum 0.7 exports `routing::any`.
        .route("/ws", any(handler))
        // Service-shaped registration mounts a tower service at a
        // single path. Common for one-off file responders.
        .route_service("/favicon.ico", ServeDir::new("assets"))
        // Sub-tree service mount — the static-files idiom.
        .nest_service("/assets", ServeDir::new("static"))
        // Catch-all fallback handler, often used to serve an SPA's
        // index.html for unknown paths.
        .fallback(handler)
        .nest(
            "/api",
            Router::new()
                .route("/users", get(handler))
                .route("/admin", post(handler)),
        )
        // Real applications often build a sub-router in a local binding before
        // mounting it. The route must inherit the nest prefix and must not also
        // appear at `/health`.
        .nest("/internal", internal_routes)
        // Real applications often keep a Router-returning function
        // per module and mount it under a prefix.
        .nest("/v1", v1_routes())
        .nest("/root", api_routes());

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();
    println!("listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

async fn handler() -> Html<&'static str> {
    Html("<h1>Hello, World!</h1>")
}

async fn search(Query(params): Query<SearchParams>) -> Html<&'static str> {
    Html(SearchService::render(params))
}

async fn submit(Form(form): Form<LoginForm>) -> Html<&'static str> {
    Html(LoginService::render(form))
}

async fn headers(headers: HeaderMap) -> Html<&'static str> {
    let request_id = headers.get("X-Request-Id");
    Html(HeaderService::render(request_id))
}

async fn session(jar: CookieJar) -> Html<&'static str> {
    let session = jar.get("session_id");
    Html(SessionService::render(session))
}

fn v1_routes() -> Router {
    Router::new()
        .route("/projects", get(handler))
        .route("/projects/{id}", get(handler))
}

fn api_routes() -> Router {
    Router::new().nest("/api", v2_routes())
}

fn v2_routes() -> Router {
    Router::new().route("/audit", get(handler))
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
            .route("/should-not-appear-post", post(handler))
            .route_service("/should-not-appear-service", ServeDir::new("x"))
            .nest_service("/should-not-appear-nest-service", ServeDir::new("y"))
            .fallback(handler);
    }
}
