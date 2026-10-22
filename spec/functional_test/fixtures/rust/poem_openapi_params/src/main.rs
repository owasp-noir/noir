use poem::{listener::TcpListener, Route, Server};
use poem_openapi::{
    param::{Header, Path, Query},
    payload::{Json, PlainText},
    Object, OpenApi, OpenApiService,
};

#[derive(Object)]
struct NewPet {
    name: String,
}

struct Api;

#[OpenApi]
impl Api {
    #[oai(path = "/pets", method = "get")]
    async fn list(&self, status: Query<Option<String>>, limit: Query<u32>) -> PlainText<String> {
        PlainText("hi".into())
    }

    #[oai(path = "/pets/:id", method = "put")]
    async fn update(
        &self,
        id: Path<i64>,
        #[oai(name = "X-API-Key")] api_key: Header<String>,
        pet: Json<NewPet>,
        session: param::Cookie<String>,
    ) -> PlainText<String> {
        PlainText("ok".into())
    }
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let api_service = OpenApiService::new(Api, "Pets", "1.0");
    let app = Route::new().nest("/api", api_service);
    Server::new(TcpListener::bind("0.0.0.0:3000")).run(app).await
}
