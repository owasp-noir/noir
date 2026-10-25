use serde::Deserialize;

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
    #[serde(default)]
    pub totp_code: Option<String>,
}

#[derive(Deserialize)]
pub struct Record<Data> {
    pub id: String,
    pub tag: String,
    pub data: Data,
}
