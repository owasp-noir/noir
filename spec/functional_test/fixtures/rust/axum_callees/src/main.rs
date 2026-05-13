use axum::{response::Html, routing::{get, post}, Json, Router};

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(home))
        .route("/profile", get(profile))
        .route("/users", post(create_user));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn home() -> Html<&'static str> {
    let status = HealthCheck::ready().await;
    Html(render_home(status))
}

async fn profile() -> Json<Profile> {
    let profile = ProfileService::load().await;
    if FeatureFlags::enabled() {
        Metrics::record_profile();
    }
    Json(ProfilePresenter::render(profile))
}

async fn create_user(Json(payload): Json<CreateUser>) -> Json<User> {
    let user = UserService::create(payload).await;
    AuditLog::write(&user);
    Json(user)
}
