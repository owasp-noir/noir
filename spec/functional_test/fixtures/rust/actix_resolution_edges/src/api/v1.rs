use actix_web::HttpResponse;

pub mod deep;

// A re-export cycle (`v1` <-> `deep`) that `missing` never resolves through.
pub use self::deep::*;

pub async fn show() -> HttpResponse {
    HttpResponse::Ok().finish()
}
