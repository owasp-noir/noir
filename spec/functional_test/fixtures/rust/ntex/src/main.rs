use ntex::web::types::{Form, Query};
use ntex::web::{self, App, HttpRequest, HttpResponse};
use serde::Deserialize;

mod appconfig;

#[derive(Deserialize)]
struct Search {
    q: String,
}

#[derive(Deserialize)]
struct Login {
    username: String,
    password: String,
}

#[derive(Deserialize)]
struct Item {
    name: String,
}

#[web::get("/users/{id}")]
async fn user(path: web::types::Path<u32>) -> impl web::Responder {
    format!("user {}", path.into_inner())
}

#[web::post("/echo")]
async fn echo(body: String) -> impl web::Responder {
    body
}

#[web::get("/search")]
async fn search(query: Query<Search>) -> HttpResponse {
    HttpResponse::Ok().body(query.q.clone())
}

#[ntex::web::put("/items/{id:\\d+}")]
async fn update_item(path: web::types::Path<u32>, item: web::types::Json<Item>) -> HttpResponse {
    HttpResponse::Ok().body(format!("{} {}", path.into_inner(), item.name))
}

#[web::post("/login")]
async fn login(form: Form<Login>) -> HttpResponse {
    HttpResponse::Ok().body(form.username.clone())
}

#[web::get("/files/{all}*")]
async fn files(path: web::types::Path<String>) -> HttpResponse {
    HttpResponse::Ok().body(path.into_inner())
}

#[web::delete("/sessions/{sid}")]
async fn logout(req: HttpRequest) -> HttpResponse {
    let _token = req.headers().get("X-Session-Token");
    HttpResponse::NoContent().finish()
}

async fn health() -> HttpResponse {
    HttpResponse::Ok().finish()
}

struct AppState;

// ntex 3: handlers bound with `to_with_state` take the state first.
async fn stats(_state: &AppState, query: web::types::Query<Search>) -> HttpResponse {
    HttpResponse::Ok().body(query.q.clone())
}

#[ntex::main]
async fn main() -> std::io::Result<()> {
    web::server(async || {
        App::new()
            .service(user)
            .service(echo)
            .route("/hey", web::get().to(|| async { "hey" }))
            .service((search, files))
            .service(
                web::scope("/api/v1").service((
                    update_item,
                    login,
                    logout,
                    web::resource("/health").route(web::get().to(health)),
                    web::resource("/stats").route(web::get().to_with_state(stats)),
                )),
            )
            .configure(appconfig::config_app)
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}

#[cfg(test)]
mod tests {
    use ntex::web;

    #[web::get("/test-only")]
    async fn test_only() -> &'static str {
        "test"
    }
}
