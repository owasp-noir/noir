// A realistic modern Loco controller. Routes are registered
// explicitly through the `Routes::new().prefix(...).add(...)` builder
// (Loco never auto-derives them from action names), handlers are plain
// `async fn` items referenced by the method-router helpers, path params
// use the brace form, and a single `.add` can register multiple verbs.
use axum::{
    extract::{Form, Json, Path, Query},
    http::HeaderMap,
};
use loco_rs::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
    page: Option<u32>,
}

#[derive(Deserialize, Serialize)]
struct CreatePostData {
    title: String,
    content: String,
}

#[derive(Deserialize)]
struct LoginForm {
    username: String,
    password: String,
}

async fn index(Query(params): Query<SearchQuery>) -> Result<impl IntoResponse> {
    let posts = PostService::list();
    let payload = PostPresenter::render(posts);
    format::json(payload)
}

async fn create(Json(data): Json<CreatePostData>) -> Result<impl IntoResponse> {
    let post = PostService::create(data);
    AuditLog::write();
    format::json(post)
}

async fn show(Path(id): Path<i32>) -> Result<impl IntoResponse> {
    format::json(())
}

async fn update(Path(id): Path<i32>, Json(data): Json<CreatePostData>) -> Result<impl IntoResponse> {
    format::json(())
}

async fn destroy(Path(id): Path<i32>) -> Result<impl IntoResponse> {
    format::json(())
}

async fn list_comments(Path(id): Path<i32>) -> Result<impl IntoResponse> {
    format::json(())
}

async fn login(Form(form): Form<LoginForm>) -> Result<impl IntoResponse> {
    format::json(())
}

async fn me(headers: HeaderMap) -> Result<impl IntoResponse> {
    let auth = headers.get("Authorization");
    format::json(())
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("/api/posts")
        .add("/", get(index).post(create))
        .add("/{id}", get(show).put(update).delete(destroy))
        .add("/{id}/comments", get(list_comments))
        .add("/login", post(login))
        .add("/me", get(me))
}
