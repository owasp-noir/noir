use actix_web::FromRequest;

pub struct GuardedData;

impl GuardedData {
    fn auth_token(req: &actix_web::HttpRequest) -> Result<Self, AuthenticationError> {
        match req.headers().get("authorization") {
            Some(_) => Ok(GuardedData),
            None => Err(AuthenticationError::MissingAuthorizationHeader),
        }
    }
}

impl FromRequest for GuardedData {
    type Error = AuthenticationError;
    type Future = std::future::Ready<Result<Self, Self::Error>>;

    fn from_request(req: &actix_web::HttpRequest, _p: &mut actix_web::dev::Payload) -> Self::Future {
        std::future::ready(Self::auth_token(req))
    }
}

pub enum AuthenticationError {
    MissingAuthorizationHeader,
}
