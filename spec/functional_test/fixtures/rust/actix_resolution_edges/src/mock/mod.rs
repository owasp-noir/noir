use actix_web::{web::Json, HttpResponse};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct MockBody {
    pub mock_field: i32,
}

pub async fn list_items(_b: Json<MockBody>) -> HttpResponse {
    HttpResponse::Ok().finish()
}
