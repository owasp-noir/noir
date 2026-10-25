use crate::{auth::User, models::CreatePost};
use actix_web::{web::Json, HttpResponse};

pub async fn create_post(Json(data): Json<CreatePost>, user: User) -> HttpResponse {
    HttpResponse::Ok().body(format!("{} {}", data.title, user.0))
}
