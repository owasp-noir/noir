use actix_web::HttpResponse;

pub async fn real() -> HttpResponse {
    HttpResponse::Ok().finish()
}
