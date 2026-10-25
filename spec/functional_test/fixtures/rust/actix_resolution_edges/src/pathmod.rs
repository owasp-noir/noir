// Decoy: `mod pathmod` is declared with `#[path = "other/real_impl.rs"]`.
use actix_web::HttpResponse;

pub async fn real() -> HttpResponse {
    HttpResponse::Ok().finish()
}
