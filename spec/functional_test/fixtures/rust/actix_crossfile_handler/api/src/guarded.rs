use crate::auth::{Admin, Anon, MaybeUser, Member};
use actix_web::HttpResponse;

pub async fn admin(_a: Admin) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn member(_m: Member) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn maybe(_u: MaybeUser) -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub async fn anon(_a: Anon) -> HttpResponse {
    HttpResponse::Ok().finish()
}
