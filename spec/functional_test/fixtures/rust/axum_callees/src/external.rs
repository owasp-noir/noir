use axum::Json;

pub async fn create_external(Json(payload): Json<ExternalPayload>) -> Json<ExternalPayload> {
    ExternalService::create(payload).await;
    Json(payload)
}
