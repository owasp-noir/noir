// poem-openapi service mounted under a nest prefix. The `#[oai]` handlers
// in `impl Api` carry only their local path; the real URL is `/api` + that
// path, because the OpenApiService wrapping `Api` is nested at `/api`. The
// `swagger_ui()` mounted at `/` must NOT drag the API impl to the root.
use poem::Route;
use poem_openapi::{param::Path, payload::PlainText, OpenApi, OpenApiService};

struct Api;

#[OpenApi]
impl Api {
    #[oai(path = "/hello", method = "get")]
    async fn hello(&self) -> PlainText<String> {
        PlainText("hi".to_string())
    }

    #[oai(path = "/users", method = "post")]
    async fn create_user(&self) -> PlainText<String> {
        PlainText("created".to_string())
    }

    #[oai(path = "/users/:id", method = "get")]
    async fn get_user(&self, id: Path<i64>) -> PlainText<String> {
        PlainText(format!("user {}", id.0))
    }
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let api_service = OpenApiService::new(Api, "Demo", "1.0").server("http://localhost:3000/api");
    let ui = api_service.swagger_ui();
    let _app = Route::new().nest("/api", api_service).nest("/", ui);
    Ok(())
}
