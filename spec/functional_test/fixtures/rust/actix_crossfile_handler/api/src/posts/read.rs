use crate::{auth::User, models::GetPost};
use actix_web::{web::Query, HttpResponse};

pub async fn get_post(q: Query<GetPost>, user: Option<User>) -> HttpResponse {
    HttpResponse::Ok().body(format!("{} {}", q.id, user.is_some()))
}
