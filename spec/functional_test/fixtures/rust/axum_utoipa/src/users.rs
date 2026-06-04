// Handlers mounted at /api/v1/users via user_routes::create_routes().
#[utoipa::path(get, path = "/")]
pub async fn list_users() {} // GET /api/v1/users

#[utoipa::path(
    get,
    path = "/{id}",
    tag = "users",
    responses((status = 200, description = "ok"))
)]
pub async fn get_user() {} // GET /api/v1/users/{id}
