use crate::consts::PREFIX;
use salvo::prelude::*;

#[handler]
async fn list_users() {}
#[handler]
async fn list_logs() {}
#[handler]
async fn dashboard() {}

// Mounted at /api (via main's push). No own path -> threads /api into its
// own pushes. Pulls in another builder fn recursively + an inline router.
pub fn build_system_route() -> Router {
    Router::new()
        .push(build_user_route()) // recursive cross-fn -> /api/system/users
        .push(Router::with_path("logs").get(list_logs)) // inline -> /api/logs
}

// Reached only through build_system_route()'s push; inherits /api.
fn build_user_route() -> Router {
    Router::with_path("system/users").get(list_users)
}

// Mounted at /api (via main's unshift). Builds its path by concatenating a
// cross-module const: PREFIX ("admin/") + "panel" -> /api/admin/panel.
pub fn build_admin_route() -> Router {
    Router::new()
        .path(PREFIX.to_owned() + "panel")
        .get(dashboard)
}
