require "../../spec_helper"
require "../../../src/miniparsers/rust_request_guards"

def rust_guard_verdicts(source : String) : Hash(String, Bool)
  facts = Noir::RustRequestGuards::Facts.new
  Noir::RustRequestGuards.scan(source, facts)
  Noir::RustRequestGuards.resolve(facts)
end

describe Noir::RustRequestGuards do
  it "treats Self:: in an inherent status_code impl as that type" do
    source = <<-RUST
      pub enum Error { Unauthorized, NotFound }
      impl Error {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::Unauthorized => StatusCode::UNAUTHORIZED,
                  Self::NotFound => StatusCode::NOT_FOUND,
              }
          }
      }
      pub struct AuthUser { id: i64 }
      impl FromRequest for AuthUser {
          type Rejection = Error;
          async fn from_request(req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
              let _h = req.headers().ok_or(Error::Unauthorized)?.get("authorization").ok_or(Error::Unauthorized)?;
              Ok(AuthUser { id: 1 })
          }
      }
      RUST
    rust_guard_verdicts(source)["AuthUser"]?.should be_true
  end

  it "lets a later inherent impl beat an earlier impl Trait for Other" do
    source = <<-RUST
      impl ResponseError for Other {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::Nope => StatusCode::UNAUTHORIZED,
              }
          }
      }
      impl<T> crate::Error<T> {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::Unauthorized => StatusCode::UNAUTHORIZED,
              }
          }
      }
      pub struct AuthUser;
      impl FromRequest for AuthUser {
          type Rejection = Error;
          async fn from_request(_req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
              Err(Error::Unauthorized)
          }
      }
      RUST
    rust_guard_verdicts(source)["AuthUser"]?.should be_true
  end

  it "does not guard a type whose only variant answers NotFound" do
    source = <<-RUST
      impl Missing {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::NotFound => StatusCode::NOT_FOUND,
              }
          }
      }
      pub struct Guest;
      impl FromRequest for Guest {
          type Rejection = Missing;
          async fn from_request(_req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
              Err(Missing::NotFound)
          }
      }
      RUST
    rust_guard_verdicts(source)["Guest"]?.should_not be_true
  end

  it "still reads Self:: from impl ResponseError for Error" do
    source = <<-RUST
      impl ResponseError for Error {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::Unauthorized => StatusCode::UNAUTHORIZED,
              }
          }
      }
      pub struct AuthUser;
      impl FromRequest for AuthUser {
          type Rejection = Error;
          async fn from_request(_req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
              Err(Error::Unauthorized)
          }
      }
      RUST
    rust_guard_verdicts(source)["AuthUser"]?.should be_true
  end

  # rust10x/rust-web-app: `CtxExt(_) => FORBIDDEN` lives in a `&self` helper
  # under `use Error::*`, not in `fn status_code` (Issue #3265).
  it "reads a &self -> StatusCode helper's arms, and only its 401/403 arms" do
    source = <<-RUST
      impl Error {
          pub fn client_status_and_error(&self) -> (StatusCode, ClientError) {
              use Error::*;
              match self {
                  CtxExt(_) => (StatusCode::FORBIDDEN, ClientError::NO_AUTH),
                  BadBody(_) => (StatusCode::BAD_REQUEST, ClientError::BAD_BODY),
                  _ => (StatusCode::INTERNAL_SERVER_ERROR, ClientError::SERVICE_ERROR),
              }
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for CtxW {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
              parts.extensions.get::<CtxExtResult>().ok_or(Error::CtxExt(CtxExtError::CtxNotInRequestExt))?.clone().map_err(Error::CtxExt)
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for CtxLoose {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
              parts.extensions.get::<CtxLoose>().cloned().ok_or(Error::CtxLoose)
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for ParsedBody {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
              parts.extensions.get::<ParsedBody>().cloned().ok_or(Error::BadBody(1))
          }
      }
      RUST
    verdicts = rust_guard_verdicts(source)
    verdicts["CtxW"]?.should be_true
    verdicts["CtxLoose"]?.should_not be_true
    verdicts["ParsedBody"]?.should_not be_true
  end

  it "reads the arms of impl IntoResponse's into_response" do
    source = <<-RUST
      impl IntoResponse for AppError {
          fn into_response(self) -> Response {
              let status = match self {
                  AppError::NotLoggedIn => StatusCode::UNAUTHORIZED,
                  AppError::Db(_) => StatusCode::INTERNAL_SERVER_ERROR,
              };
              status.into_response()
          }
      }
      impl<S> FromRequestParts<S> for CurrentUser {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, AppError> {
              parts.extensions.get::<CurrentUser>().cloned().ok_or(AppError::NotLoggedIn)
          }
      }
      impl<S> FromRequestParts<S> for DbConn {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, AppError> {
              parts.extensions.get::<DbConn>().cloned().ok_or(AppError::Db(1))
          }
      }
      RUST
    verdicts = rust_guard_verdicts(source)
    verdicts["CurrentUser"]?.should be_true
    verdicts["DbConn"]?.should_not be_true
  end

  # launchbadge/realworld-axum-sqlx: into_response's arm for the variant
  # defers to `self.status_code()`, which is what maps it to 401.
  it "leaves a variant to status_code when into_response's arm names no status" do
    source = <<-RUST
      impl Error {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::Unauthorized => StatusCode::UNAUTHORIZED,
                  Self::Sqlx(_) => StatusCode::INTERNAL_SERVER_ERROR,
              }
          }
      }
      impl IntoResponse for Error {
          fn into_response(self) -> Response<Self::Body> {
              match self {
                  Self::Unauthorized => {
                      return (self.status_code(), self.to_string()).into_response();
                  }
                  Self::Sqlx(ref e) => {
                      log::error!("SQLx error: {:?}", e);
                  }
                  _ => (),
              }
              (self.status_code(), self.to_string()).into_response()
          }
      }
      impl FromRequest for AuthUser {
          type Rejection = Error;
          async fn from_request(req: &mut RequestParts<Body>) -> Result<Self, Self::Rejection> {
              req.headers().get(AUTHORIZATION).ok_or(Error::Unauthorized)?;
              Ok(AuthUser)
          }
      }
      RUST
    rust_guard_verdicts(source)["AuthUser"]?.should be_true
  end

  it "does not read a handler that returns a StatusCode as a status mapping" do
    source = <<-RUST
      async fn lookup(id: Path<i64>) -> Result<Json<Item>, StatusCode> {
          match find(id) {
              AppError::Missing => Err(StatusCode::UNAUTHORIZED),
          }
      }
      impl<S> FromRequestParts<S> for ItemRef {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, AppError> {
              parts.extensions.get::<ItemRef>().cloned().ok_or(AppError::Missing)
          }
      }
      RUST
    rust_guard_verdicts(source)["ItemRef"]?.should_not be_true
  end
end
