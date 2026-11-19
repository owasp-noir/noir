use poem_openapi::{param::Path, payload::PlainText, OpenApi};

pub struct UsersApi;

#[OpenApi]
impl UsersApi {
    #[oai(path = "/users/:id", method = "get")]
    async fn get_user(&self, id: Path<u64>) -> PlainText<String> {
        PlainText("x".into())
    }
}
