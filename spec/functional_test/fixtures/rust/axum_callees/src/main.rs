use axum::{response::Html, routing::{get, post}, Json, Router};

mod external;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(home))
        .route("/profile", get(profile))
        .route("/users", post(create_user))
        .route("/external", post(external::create_external));

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

fn extra_routes() -> Router {
    Router::new()
        .route("/account", get(read_account).put(account::update_account))
}

fn builder_routes() -> Router {
    AuthenticatedRouteBuilder::new()
        .get("/builder", builder_get, vec![1])
        .unauthenticated_post("/builder-public", builder_public)
        .build()
}

async fn read_account() -> Json<Account> {
    let account = AccountService::read().await;
    Json(account)
}

mod account {
    pub async fn update_account() {
        AccountService::update().await;
        AuditLog::write_update();
    }
}

async fn builder_get() {
    BuilderService::read().await;
}

async fn builder_public() {
    BuilderService::create().await;
}

fn scoped_routes() -> Router {
    Router::new().route("/scoped", get(api::shared_handler))
}

fn builder_false_positives() {
    FormBuilder::new().get("/not-route", validate);
}

async fn shared_handler() {
    WrongService::hit().await;
}

async fn validate() {
    Validator::check().await;
}

mod api {
    pub async fn shared_handler() {
        RightService::hit().await;
    }
}
