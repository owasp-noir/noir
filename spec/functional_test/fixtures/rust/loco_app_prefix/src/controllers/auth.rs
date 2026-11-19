use axum::debug_handler;
use loco_rs::prelude::*;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct RegisterParams {
    pub email: String,
    pub password: String,
}

#[debug_handler]
async fn register(State(ctx): State<AppContext>, Json(params): Json<RegisterParams>) -> Result<Response> {
    format::json(())
}

#[debug_handler]
async fn verify(State(ctx): State<AppContext>, Path(token): Path<String>) -> Result<Response> {
    format::json(())
}

#[debug_handler]
async fn current(auth: auth::JWT, State(ctx): State<AppContext>) -> Result<Response> {
    format::json(())
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("/auth")
        .add("/register", post(register))
        .add("/verify/{token}", get(verify))
        .add("/current", get(current))
}
