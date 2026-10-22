// 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 서버 함수는 테스트 모듈 바로 위에 있어도 누락되면 안 됩니다. 
use leptos::prelude::*;
use server_fn::codec::{GetUrl, Json, PatchJson};

#[component]
pub fn App() -> impl IntoView {
    view! { <p>"hello"</p> }
}

#[server]
pub async fn get_user(id: u32, mut name: String) -> Result<String, ServerFnError> {
    load_user(id, &name).await
}

#[server(GetPost, "/api/v2", "GetJson")]
pub async fn get_post(slug: String) -> Result<String, ServerFnError> {
    Ok(slug)
}

#[server(prefix = "/custom", endpoint = "add_todo")]
pub async fn add_todo(title: String) -> Result<(), ServerFnError> {
    Ok(())
}

#[server(input = GetUrl)]
pub async fn list_todos(query: String, page: u32) -> Result<Vec<String>, ServerFnError> {
    Ok(vec![])
}

#[server(input = Json, output = Json)]
pub async fn save_settings(theme: String) -> Result<(), ServerFnError> {
    Ok(())
}

#[server(input = PatchJson, endpoint = "/todo/update")]
pub async fn update_todo(id: u32, done: bool) -> Result<(), ServerFnError> {
    Ok(())
}

/// Live counter.
#[leptos::server(protocol = Websocket<JsonEncoding, JsonEncoding>)]
pub async fn counter_stream(input: BoxedStream<i32, ServerFnError>) -> Result<BoxedStream<i32, ServerFnError>, ServerFnError> {
    Ok(input)
}

#[server(
    // GetUrl sends the arguments, as a query string
    input = GetUrl,
    endpoint = "commented", /* fixed path */
)]
pub async fn commented(term: String) -> Result<(), ServerFnError> {
    Ok(())
}

#[server(Lower, "/api", "getjson")]
pub async fn lower(r#type: String, _: u8) -> Result<(), ServerFnError> {
    Ok(())
}

#[server(endpoint = "")]
pub async fn empty_ep() -> Result<(), ServerFnError> {
    Ok(())
}

#[cfg(test)]
mod tests {
    #[server]
    pub async fn only_in_tests() -> Result<(), ServerFnError> {
        Ok(())
    }
}
