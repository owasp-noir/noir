use crate::error::AppError;
use crate::error::AppError::*;
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

/// Refuses through `.ok_or(...)` with a variant on the second line of a
/// `|` alternation.
#[derive(Clone)]
pub struct Admin(pub String);

impl FromRequest for Admin {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        ready(req.extensions().get::<Admin>().cloned().ok_or(AppError::NotAdmin))
    }
}

/// Refuses with a glob-imported variant mapped by a `Self::` block arm.
pub struct Member;

impl FromRequest for Member {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        if req.extensions().get::<User>().is_none() {
            return ready(Err(Banned));
        }
        ready(Ok(Member))
    }
}

/// Builds a 401 error but never returns it: anonymous callers get through.
pub struct MaybeUser(pub Option<User>);

impl FromRequest for MaybeUser {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        let user: Result<User, AppError> = req.extensions().get::<User>().cloned().ok_or(AppError::NotLoggedIn);
        ready(Ok(MaybeUser(user.ok())))
    }
}

/// Matches on a 401 error, then admits the caller.
pub struct Anon;

impl FromRequest for Anon {
    type Error = AppError;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _payload: &mut Payload) -> Self::Future {
        let found: Result<(), AppError> = req.extensions().get::<User>().map(|_| ()).ok_or(AppError::NotLoggedIn);
        ready(match found {
            Ok(()) => Ok(Anon),
            Err(AppError::NotLoggedIn) => Ok(Anon),
            Err(e) => Err(e),
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
