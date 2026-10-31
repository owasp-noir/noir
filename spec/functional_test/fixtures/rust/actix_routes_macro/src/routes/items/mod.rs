use actix_web::web;
use actix_web::HttpResponse;

use crate::auth::GuardedData;

#[routes::routes(
    routes(
        "" => [get(list_items), post(create_item)],
        "/{item_id}" => [get(get_item), delete(delete_item)],
        "/{item_id}/tags" => sub(TagsApi),
    ),
    tag = "Items",
)]
pub struct ItemsApi;

#[routes::routes(
    routes("" => get(list_tags)),
    tag = "Tags",
)]
pub struct TagsApi;

#[derive(serde::Deserialize)]
#[deserr(rename_all = camelCase)]
pub struct ListQuery {
    page_size: Option<u32>,
}

pub async fn list_items(
    _auth: GuardedData,
    params: AwebQueryParameter<ListQuery, ApiError>,
) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn create_item(_auth: GuardedData, body: web::Json<serde_json::Value>) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn get_item(item_id: web::Path<String>) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn delete_item(_auth: GuardedData, item_id: web::Path<String>) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn list_tags(item_id: web::Path<String>) -> HttpResponse {
    HttpResponse::Ok().finish()
}
