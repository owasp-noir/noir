use actix_web::{web, HttpResponse};

pub async fn shared(body: web::Json<String>) -> HttpResponse {
    ShadowService::store(body.into_inner());
    HttpResponse::Ok().finish()
}
