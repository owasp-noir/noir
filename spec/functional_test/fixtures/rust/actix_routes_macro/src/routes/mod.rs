pub mod items;
pub mod other;

use actix_web::HttpResponse;

#[routes::routes(
    routes(
        "/health" => get(health),
        // The rest is mounted per module: "/commented" => get(nope),
        "/items" => sub(items::ItemsApi),
        "/other" => sub(other::ItemsApi),
    ),
    tag = "Root",
)]
pub struct RootApi;

async fn health() -> HttpResponse {
    HttpResponse::Ok().finish()
}
