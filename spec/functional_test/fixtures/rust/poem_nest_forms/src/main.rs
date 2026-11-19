use poem::{get, handler, listener::TcpListener, post, Route, Server};
use poem_openapi::{payload::PlainText, OpenApi, OpenApiService};

mod admin;

#[handler]
fn list_users() -> String { "users".into() }

#[handler]
fn create_user() -> String { "created".into() }

struct PetApi;

#[OpenApi]
impl PetApi {
    #[oai(path = "/pets", method = "get")]
    async fn list_pets(&self) -> PlainText<String> { PlainText("pets".into()) }
}

struct StoreApi;

#[OpenApi(prefix_path = "/store")]
impl StoreApi {
    #[oai(path = "/orders", method = "post")]
    async fn place_order(&self) -> PlainText<String> { PlainText("order".into()) }
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    // (a) a let-bound sub-router nested by name
    let users = Route::new().at("/", get(list_users).post(create_user));

    // (b) several API structs combined in one service, the documented tuple form
    let api_service = OpenApiService::new((PetApi, StoreApi), "Demo", "1.0").server("/api");
    let ui = api_service.swagger_ui();

    let app = Route::new()
        .nest("/users", users)
        .nest("/admin", admin::routes())
        .nest("/api", api_service)
        .nest("/docs", ui);

    Server::new(TcpListener::bind("0.0.0.0:3000")).run(app).await
}
