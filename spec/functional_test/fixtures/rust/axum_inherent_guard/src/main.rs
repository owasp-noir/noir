use axum::{routing::post, Router};

pub enum Error {
    Unauthorized,
    NotFound,
}
impl Error {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
            Self::NotFound => StatusCode::NOT_FOUND,
        }
    }
}
pub struct AuthUser {
    id: i64,
}
#[async_trait]
impl FromRequest for AuthUser {
    type Rejection = Error;
    async fn from_request(req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
        let h = req
            .headers()
            .ok_or(Error::Unauthorized)?
            .get("authorization")
            .ok_or(Error::Unauthorized)?;
        Ok(AuthUser { id: 1 })
    }
}
async fn create_item(auth_user: AuthUser) -> &'static str {
    "ok"
}

pub enum Missing {
    NotFound,
}
impl Missing {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::NotFound => StatusCode::NOT_FOUND,
        }
    }
}
pub struct Guest {
    id: i64,
}
#[async_trait]
impl FromRequest for Guest {
    type Rejection = Missing;
    async fn from_request(_req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
        Err(Missing::NotFound)
    }
}
async fn list_items(_guest: Guest) -> &'static str {
    "ok"
}

pub enum ApiError {
    Denied,
}
impl ResponseError for ApiError {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::Denied => StatusCode::FORBIDDEN,
        }
    }
}
pub struct AdminUser {
    id: i64,
}
#[async_trait]
impl FromRequest for AdminUser {
    type Rejection = ApiError;
    async fn from_request(_req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
        Err(ApiError::Denied)
    }
}
async fn admin_item(_admin: AdminUser) -> &'static str {
    "ok"
}

fn main() {
    let app: Router = Router::new()
        .route("/items", post(create_item))
        .route("/missing", post(list_items))
        .route("/admin", post(admin_item));
}
