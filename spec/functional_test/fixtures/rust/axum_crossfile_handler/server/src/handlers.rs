use axum::extract::Query;
use axum::Json;
use my_domain::api::{LoginRequest, Record};
use serde::de::DeserializeOwned;
use serde::Deserialize;
use std::collections::HashMap;

pub struct Session;
impl Session {
    pub fn login(&self, Json(w): Json<Wrong>) {}
}

#[derive(Deserialize)]
pub struct Wrong {
    pub wrong_field: String,
}

pub async fn login(Json(req): Json<LoginRequest>) -> String {
    req.username
}

pub async fn push(Json(records): Json<Vec<Record<String>>>) -> usize {
    records.len()
}

#[derive(Deserialize)]
pub struct PurgeParams {}

pub async fn purge(_params: Query<PurgeParams>) {}

mod legacy {
    #[derive(serde::Deserialize)]
    pub struct Paging {
        pub old_name: String,
    }
}

#[derive(Deserialize)]
pub struct Paging {
    pub page: u32,
    pub per_page: u32,
}

#[derive(Deserialize)]
pub struct ListReq {
    #[serde(flatten)]
    pub paging: Paging,
}

#[derive(Deserialize)]
pub struct Search {
    pub q: String,
    #[serde(flatten)]
    pub paging: Option<Paging>,
}

#[derive(Deserialize)]
pub struct Loose {
    pub kind: String,
    #[serde(flatten)]
    pub extra: HashMap<String, String>,
}

pub async fn list(Query(p): Query<ListReq>) {}

pub async fn search(Json(s): Json<Search>) {}

pub async fn loose(Json(l): Json<Loose>) {}

#[derive(Deserialize)]
pub struct T {
    pub unrelated: String,
}

pub async fn generic<T: DeserializeOwned>(Json(b): Json<T>) {}
