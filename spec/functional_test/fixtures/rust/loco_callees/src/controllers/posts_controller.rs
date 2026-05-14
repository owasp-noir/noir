use axum::{
    extract::{Form, Json, Path},
    http::HeaderMap,
};
use loco_rs::prelude::*;

pub struct PostsController;

impl PostsController {
    pub async fn index() -> Result<impl IntoResponse> {
        let posts = PostService::list();
        let payload = PostPresenter::render(posts);
        Ok(Json(payload))
    }

    pub async fn show(Path(id): Path<i64>) -> Result<impl IntoResponse> {
        let post = PostService::load(id);
        AuditLog::read_post();
        let payload = PostPresenter::render(post);
        Ok(Json(payload))
    }

    pub async fn create(Json(data): Json<CreatePostData>) -> Result<impl IntoResponse> {
        let post = PostService::create(data);
        AuditLog::write();
        let payload = PostPresenter::render(post);
        Ok(Json(payload))
    }

    pub async fn users(headers: HeaderMap) -> Result<impl IntoResponse> {
        let auth = headers.get("Authorization");
        AuthService::validate(auth);
        Ok(Json(UserPresenter::list()))
    }

    pub async fn login(Form(form): Form<LoginForm>) -> Result<impl IntoResponse> {
        let session = AuthService::login(form);
        AuditLog::write();
        Ok(Json(SessionPresenter::render(session)))
    }
}
