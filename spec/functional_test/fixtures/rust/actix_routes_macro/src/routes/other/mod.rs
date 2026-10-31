use actix_web::HttpResponse;

#[routes::routes(
    routes("/ping" => get(ping)),
    tag = "Other",
)]
pub struct ItemsApi;

pub async fn ping() -> HttpResponse {
    HttpResponse::Ok().finish()
}
