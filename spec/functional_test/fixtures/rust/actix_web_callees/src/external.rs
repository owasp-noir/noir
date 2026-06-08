use actix_web::{web, HttpResponse};

use super::UserInfo;

pub async fn external_create(body: web::Json<UserInfo>) -> HttpResponse {
    let user = ExternalService::create(body.into_inner()).await;
    HttpResponse::Created().json(user)
}
