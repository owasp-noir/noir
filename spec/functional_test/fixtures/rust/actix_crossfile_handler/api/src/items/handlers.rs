use crate::auth::Locale;
use actix_web::HttpResponse;

pub async fn list(locale: Locale) -> HttpResponse {
    HttpResponse::Ok().body(locale.0)
}
