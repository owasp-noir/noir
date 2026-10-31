pub mod items;
pub mod other;
pub mod settings;

use actix_web::HttpResponse;

#[routes::routes(
    routes(
        "/health" => get(health),
        // The rest is mounted per module: "/commented" => get(nope),
        "/items" => sub(items::ItemsApi),
        "/other" => sub(other::ItemsApi),
        "/settings" => sub(settings::SettingsApi),
    ),
    tag = "Root",
)]
pub struct RootApi;

async fn health() -> HttpResponse {
    HttpResponse::Ok().finish()
}
