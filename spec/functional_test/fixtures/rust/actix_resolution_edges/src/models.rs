use serde::Deserialize;

#[derive(Deserialize)]
pub struct ItemQuery {
    pub page: i32,
}
