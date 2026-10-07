use dioxus::prelude::*;

fn main() {
    dioxus::launch(App);
}

#[component]
fn App() -> Element {
    rsx! { "hello" }
}

#[server]
async fn get_dogs(breed: String) -> Result<Vec<String>> {
    Ok(vec![breed])
}

#[server(prefix = "/api/custom", endpoint = "my_anonymous", headers: dioxus_fullstack::HeaderMap)]
async fn anonymous() -> Result<()> {
    Ok(())
}

#[get("/api/users/{id}?page&limit")]
async fn get_user(id: u32, page: u32, limit: u32) -> Result<String> {
    Ok(String::new())
}

#[post("/api/{user_id}/chat?room_id", headers: dioxus_fullstack::HeaderMap)]
async fn chat(user_id: u32, room_id: String, message: String) -> Result<()> {
    Ok(())
}

#[put("/api/items/:id")]
async fn put_item(id: u32, item: String) -> Result<()> {
    Ok(())
}

#[delete("/api/items/{id}")]
async fn delete_item(id: u32) -> Result<()> {
    Ok(())
}

#[patch("/api/profile", auth: auth::Session)]
async fn update_profile(mut nickname: String) -> Result<()> {
    Ok(())
}

#[get("/api/search?:filters")]
async fn search(filters: SearchQuery) -> Result<Vec<String>> {
    Ok(vec![])
}

#[server(endpoint = "login", session: auth::Session)]
async fn login(username: String) -> Result<()> {
    Ok(())
}

#[get("/files/{name}.json" /* served raw */)]
async fn file(name: String) -> Result<String> {
    Ok(name)
}
