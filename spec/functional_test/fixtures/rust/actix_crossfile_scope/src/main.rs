// Router setup file. The scope tree lives here, but the `#[get]` /
// `#[post]` handlers it mounts are defined in *other* modules
// (`users.rs`, `posts.rs`, `admin.rs`). This is the rauthy-style
// cross-file scope composition the analyzer must resolve: a handler's
// real URL is its attribute path prefixed by the scope it is
// registered under in this file, not in its own file.
use actix_web::{web, App, HttpServer};

mod admin;
mod posts;
mod users;

// `api_services()` returns the composed scope; it is mounted via
// `.service(api_services())`, so the prefix is only discoverable by
// walking this function body (a different file from the handlers).
fn api_services() -> actix_web::Scope {
    web::scope("/auth")
        // registered directly under /auth
        .service(users::get_me)
        .service(
            web::scope("/v1")
                // registered under /auth/v1
                .service(users::list_users)
                .service(posts::create_post)
                // collision: `list` also exists in `admin` — module-aware
                // matching must keep them apart.
                .service(posts::list),
        )
}

// A second, independent top-level scope in the same router file.
fn admin_services() -> actix_web::Scope {
    web::scope("/admin")
        .service(admin::dashboard)
        .service(admin::list)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .service(api_services())
            .service(admin_services())
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
