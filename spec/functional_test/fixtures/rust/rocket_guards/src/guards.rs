use rocket::http::Status;
use rocket::outcome::try_outcome;
use rocket::request::{FromRequest, Outcome, Request};

macro_rules! deny {
    ($msg:expr) => {{
        return Outcome::Error((Status::Unauthorized, $msg));
    }};
}

pub struct Session {
    pub user: String,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for Session {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Authorization") {
            Some(token) => Outcome::Success(Session { user: token.to_string() }),
            None => deny!("missing token"),
        }
    }
}

pub struct OrgSession {
    pub session: Session,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for OrgSession {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        let session = try_outcome!(Session::from_request(req).await);
        Outcome::Success(OrgSession { session })
    }
}

pub struct Ip(pub String);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for Ip {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        Outcome::Success(Ip(req.remote().map(|r| r.to_string()).unwrap_or_default()))
    }
}

// Refuses only when `Ip` fails, and `Ip` never does.
pub struct ClientInfo {
    pub ip: Ip,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for ClientInfo {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        let Outcome::Success(ip) = Ip::from_request(req).await else {
            deny!("no ip")
        };
        Outcome::Success(ClientInfo { ip })
    }
}

// Named like an auth guard, but only rejects malformed input.
pub struct AuthUser(pub String);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for AuthUser {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("X-Hint") {
            Some(h) => Outcome::Success(AuthUser(h.to_string())),
            None => Outcome::Error((Status::BadRequest, "missing hint")),
        }
    }
}
