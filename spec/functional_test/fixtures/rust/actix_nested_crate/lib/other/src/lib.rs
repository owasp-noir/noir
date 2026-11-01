// A sibling crate that does not depend on actix-web: the route-looking
// attribute below is text in its own DSL, not an actix endpoint.
#[get("/stray")]
async fn stray() -> HttpResponse {
    HttpResponse::Ok().finish()
}

pub fn build() -> App {
    App::new().route("/stray-too", get().to(stray))
}
