use axum::extract::Query;
use axum::Json;
use my_domain::api::{LoginRequest, Record};
use serde::Deserialize;

pub async fn login(Json(req): Json<LoginRequest>) -> String {
    req.username
}

pub async fn push(Json(records): Json<Vec<Record<String>>>) -> usize {
    records.len()
}

#[derive(Deserialize)]
pub struct PurgeParams {}

pub async fn purge(_params: Query<PurgeParams>) {}
