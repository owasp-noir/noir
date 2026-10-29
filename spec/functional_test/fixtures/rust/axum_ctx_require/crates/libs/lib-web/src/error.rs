use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

pub type Result<T> = core::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    CtxExt(String),
    CtxLoose(String),
    BadBody(String),
}

impl IntoResponse for Error {
    fn into_response(self) -> Response {
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    }
}

impl Error {
    pub fn client_status_and_error(&self) -> (StatusCode, &'static str) {
        use Error::*;

        match self {
            CtxExt(_) => (StatusCode::FORBIDDEN, "NO_AUTH"),
            BadBody(_) => (StatusCode::BAD_REQUEST, "BAD_BODY"),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, "SERVICE_ERROR"),
        }
    }
}
