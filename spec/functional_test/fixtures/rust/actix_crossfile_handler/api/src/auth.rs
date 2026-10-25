use crate::error::AppError;
use actix_web::{dev::Payload, FromRequest, HttpMessage, HttpRequest};
use std::future::{ready, Ready};

/// Put into the request extensions by a session middleware that never
/// rejects; this extractor is what turns an anonymous caller away.
#[derive(Clone)]
pub struct User(pub String);

impl FromRequest for User {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        ready(match req.extensions().get::<User>() {
            Some(u) => Ok(u.clone()),
            None => Err(AppError::NotLoggedIn),
        })
    }
}

/// Fails with a 400 when absent: not an auth guard.
pub struct Locale(pub String);

impl FromRequest for Locale {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        ready(match req.extensions().get::<String>() {
            Some(l) => Ok(Locale(l.clone())),
            None => Err(AppError::Invalid),
        })
    }
}
