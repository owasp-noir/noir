use axum::debug_handler;
use loco_rs::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Params {
    pub title: Option<String>,
    pub content: Option<String>,
}

#[debug_handler]
pub async fn list(State(ctx): State<AppContext>) -> Result<Response> {
    format::json(())
}

#[debug_handler]
pub async fn add(State(ctx): State<AppContext>, Json(params): Json<Params>) -> Result<Response> {
    format::json(())
}

#[debug_handler]
pub async fn update(Path(id): Path<i32>, State(ctx): State<AppContext>, Json(params): Json<Params>) -> Result<Response> {
    format::json(())
}

#[debug_handler]
pub async fn remove(Path(id): Path<i32>, State(ctx): State<AppContext>) -> Result<Response> {
    format::empty()
}

#[debug_handler]
pub async fn get_one(Path(id): Path<i32>, State(ctx): State<AppContext>) -> Result<Response> {
    format::json(())
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("api/notes/")
        .add("/", get(list))
        .add("/", post(add))
        .add(":id", get(get_one))
        .add("/{id}", delete(remove))
        .add("{id}", put(update))
        .add("{id}", patch(update))
}

pub fn not_routes() {
    let mut seen = Registry::default();
    seen.add("not-a-route", get(list));
}
