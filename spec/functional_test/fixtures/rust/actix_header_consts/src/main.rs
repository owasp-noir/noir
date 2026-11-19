use actix_web::{get, http::header, HttpRequest, HttpResponse, Responder};

#[get("/literal")]
async fn literal(req: HttpRequest) -> impl Responder {
    let _a = req.headers().get("x-api-key");
    HttpResponse::Ok()
}

#[get("/consts")]
async fn consts(req: HttpRequest) -> impl Responder {
    let _a = req.headers().get(header::AUTHORIZATION);
    let _b = req.headers().get(actix_web::http::header::USER_AGENT);
    HttpResponse::Ok()
}
