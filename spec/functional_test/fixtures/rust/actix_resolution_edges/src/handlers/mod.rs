use crate::models::ItemQuery;
use actix_web::{web::Query, HttpResponse};

pub async fn list_items(_q: Query<ItemQuery>) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn show_item(_p: Query<crate::Paging>) -> HttpResponse {
    HttpResponse::Ok().finish()
}
