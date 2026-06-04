// `method(get, post)` form -> both verbs at /api/v1/admin/dashboard.
#[utoipa::path(method(get, post), path = "/dashboard")]
pub async fn dashboard() {}
