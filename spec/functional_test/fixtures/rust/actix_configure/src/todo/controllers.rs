use actix_web::{get, post, web, HttpResponse};

#[get("/")]
async fn list_todos() -> HttpResponse {
    HttpResponse::Ok().finish()
}

#[post("/")]
async fn create_todo(body: web::Json<String>) -> HttpResponse {
    TodoService::create(body.into_inner());
    HttpResponse::Ok().finish()
}

pub fn init_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(list_todos);
    cfg.service(create_todo);
}
