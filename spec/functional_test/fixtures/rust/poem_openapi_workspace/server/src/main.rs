use poem::{listener::TcpListener, Route, Server};
use poem_openapi::OpenApiService;

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let api_service = OpenApiService::new(api::UsersApi, "Users", "1.0");
    let app = Route::new().nest("/api", api_service);
    Server::new(TcpListener::bind("0.0.0.0:3000")).run(app).await
}
