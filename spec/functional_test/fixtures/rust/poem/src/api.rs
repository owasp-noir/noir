use poem_openapi::{payload::Json, OpenApi};

pub struct Api;

#[OpenApi]
impl Api {
    #[oai(path = "/api/items", method = "get")]
    async fn list_items(&self) -> Json<Vec<String>> {
        Json(vec![])
    }

    #[oai(path = "/api/items/:id", method = "post")]
    async fn create_item(&self, body: Json<serde_json::Value>) -> Json<String> {
        Json("ok".to_string())
    }
}
