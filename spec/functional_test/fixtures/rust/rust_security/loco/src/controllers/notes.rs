use axum::extract::Json;
use loco_rs::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize)]
struct NoteData {
    title: String,
    body: String,
}

async fn index() -> Result<impl IntoResponse> {
    format::json(())
}

async fn create(Json(data): Json<NoteData>) -> Result<impl IntoResponse> {
    format::json(())
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("/api/notes")
        .add("/", get(index).post(create))
}
