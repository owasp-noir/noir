use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    routing::{get, post, MethodRouter},
    Router,
};
use axum_extra::{headers::Authorization, headers::authorization::Bearer, TypedHeader};
use std::collections::HashMap;
use tower_http::services::ServeDir;

#[derive(Clone)]
struct AppState;

fn api_routes() -> Router<AppState> {
    Router::new()
        .route("/users/{id}", get(get_user))
        .route("/files/{*path}", get(get_file))
        .route("/me", get(me))
        .route("/upload", post(upload))
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .nest("/api", api_routes())
        .nest_service("/assets", ServeDir::new("assets"))
        .route("/search", get(search))
        .with_state(AppState);
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn get_user(State(_s): State<AppState>, Path(id): Path<u64>) -> String { id.to_string() }
async fn get_file(Path(path): Path<String>) -> String { path }
async fn me(TypedHeader(auth): TypedHeader<Authorization<Bearer>>) -> String { auth.token().to_string() }
async fn upload(
    TypedHeader(ua): TypedHeader<axum_extra::headers::UserAgent>,
    ct: Option<TypedHeader<headers::ContentType>>,
) -> String { ua.to_string() }
async fn search(Query(params): Query<HashMap<String, String>>, headers: HeaderMap) -> String {
    let ua = headers.get("user-agent");
    String::new()
}
