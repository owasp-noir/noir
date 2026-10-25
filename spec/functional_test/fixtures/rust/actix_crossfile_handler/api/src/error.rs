use actix_web::{http::StatusCode, ResponseError};

#[derive(Debug)]
pub enum AppError {
    NotLoggedIn,
    NotAdmin,
    Banned,
    Invalid,
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl ResponseError for AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            AppError::NotLoggedIn
            | AppError::NotAdmin => StatusCode::UNAUTHORIZED,
            Self::Banned => {
                StatusCode::FORBIDDEN
            }
            AppError::Invalid => StatusCode::BAD_REQUEST,
        }
    }
}
