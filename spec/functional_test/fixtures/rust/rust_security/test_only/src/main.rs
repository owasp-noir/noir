use actix_web::{web, App, get, HttpResponse};
use actix_cors::Cors;

// The only production endpoint. It has NO security middleware in real
// code — every protection below lives in a #[cfg(test)] module and must
// be ignored by the tagger.
#[get("/widget")]
async fn widget() -> HttpResponse {
    HttpResponse::Ok().body("w")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build() {
        let _app = App::new()
            .wrap(Cors::permissive())
            .app_data(web::JsonConfig::default().limit(64));
    }
}
