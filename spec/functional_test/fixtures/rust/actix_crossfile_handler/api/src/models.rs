use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatePost {
    pub title: String,
    pub community_id: i32,
    pub body: Option<String>,
}

#[derive(Deserialize)]
pub struct GetPost {
    pub id: i32,
    pub comment_id: Option<i32>,
}
