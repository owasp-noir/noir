use axum::{routing::get, Router};

// Mounted at `/web` from main.rs — these routes must surface as `/web/` and
// `/web/assets/app.js`, not at the root.
pub fn make_webui_router() -> Router {
    Router::new()
        .route("/", get(index))
        .route("/assets/app.js", get(asset))
}

async fn index() {}
async fn asset() {}
