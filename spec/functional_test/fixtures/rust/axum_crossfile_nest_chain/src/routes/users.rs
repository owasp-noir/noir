use axum::{
    extract::{Path, Query, Json, Form},
    routing::{get, post},
    http::HeaderMap,
    Router,
};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct ListParams {
    page: Option<u32>,
    per_page: Option<u32>,
}

#[derive(Deserialize)]
pub struct CreateUser {
    name: String,
    email: String,
}

pub fn router() -> Router {
    Router::new()
        .route("/", get(list_users).post(create_user))
        .route("/:id", get(get_user).delete(delete_user).put(update_user))
        .route("/:id/avatar", post(upload_avatar))
}

async fn list_users(Query(params): Query<ListParams>) -> String {
    format!("{:?}", params.page)
}

async fn create_user(Json(payload): Json<CreateUser>) -> String {
    payload.name
}

async fn get_user(Path(id): Path<u64>, headers: HeaderMap) -> String {
    let _ = headers.get("x-request-id");
    id.to_string()
}

async fn delete_user(Path(id): Path<u64>) {}

async fn update_user(Path(id): Path<u64>, Form(f): Form<CreateUser>) {}

async fn upload_avatar(Path(id): Path<u64>) {}
