use poem_openapi::{payload::Json, OpenApi};

pub struct Api;

#[OpenApi]
impl Api {
    #[oai(path = "/api/items/:id", method = "post")]
    async fn create_item(&self, body: Json<serde_json::Value>) -> Json<String> {
        let item = ItemService::create(body);
        AuditLog::write(&item);
        let rendered = ItemPresenter::render(item);
        Json(rendered)
    }
}
