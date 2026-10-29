require "../../spec_helper"
require "../../../src/miniparsers/rust_request_guards"

def rust_guard_verdicts(source : String) : Hash(String, Bool)
  facts = Noir::RustRequestGuards::Facts.new
  Noir::RustRequestGuards.scan(source, facts)
  Noir::RustRequestGuards.resolve(facts)
end

# Verdicts over several files, each scanned under its own path.
def rust_guard_verdicts_in(files : Hash(String, String)) : Hash(String, Bool)
  facts = Noir::RustRequestGuards::Facts.new
  files.each { |path, source| Noir::RustRequestGuards.scan(source, facts, path) }
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

  it "reads the arms of many impls in one non-ASCII file in linear time" do
    rejections = (0...2000).join do |i|
      %(pub struct Rej#{i};\nimpl Rej#{i} {\n    pub fn new() -> Self { Rej#{i} }\n}\n) +
        %(impl IntoResponse for Rej#{i} {\n    fn into_response(self) -> Response {\n) +
        %(        (StatusCode::BAD_REQUEST, "거절 #{i}").into_response()\n    }\n}\n)
    end
    source = %(use axum::http::StatusCode;\nconst NOTE: &str = "한국어";\n) + rejections + <<-RUST
      impl IntoResponse for AppError {
          fn into_response(self) -> Response {
              match self {
                  AppError::NotLoggedIn => (StatusCode::UNAUTHORIZED, "로그인").into_response(),
              }
          }
      }
      impl<S> FromRequestParts<S> for CurrentUser {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, AppError> {
              parts.extensions.get::<CurrentUser>().cloned().ok_or(AppError::NotLoggedIn)
          }
      }
      RUST
    verdicts = {} of String => Bool
    elapsed = Time.measure { verdicts = rust_guard_verdicts(source) }
    verdicts["CurrentUser"]?.should be_true
    elapsed.should be < 2.seconds
  end

  # Two `enum Error` in one crate: the extractor's own file defines the one
  # it returns, whose catch-all answers 400; the other file's 401 for the
  # same-named variant is not it.
  it "reads a variant in the mapping of the file that defines its enum" do
    auth = <<-RUST
      pub enum Error { MissingHeader, BadToken }
      impl Error {
          pub fn http_status(&self) -> StatusCode {
              match self {
                  Error::MissingHeader => StatusCode::UNAUTHORIZED,
                  Error::BadToken => StatusCode::UNAUTHORIZED,
              }
          }
      }
      RUST
    ct = <<-RUST
      pub enum Error { MissingHeader, Db }
      impl IntoResponse for Error {
          fn into_response(self) -> Response {
              match self {
                  Error::Db => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
                  _ => StatusCode::BAD_REQUEST.into_response(),
              }
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for ContentType {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
              parts.headers.get("content-type").map(|v| ContentType(format!("{v:?}"))).ok_or(Error::MissingHeader)
          }
      }
      RUST
    rust_guard_verdicts_in({File.join("src", "auth.rs") => auth, File.join("src", "ct.rs") => ct})["ContentType"]?.should_not be_true

    # The same extractor beside the 401 mapping is a guard.
    own = auth + ct.sub(/pub enum Error \{[^}]*\}/, "").sub(/impl IntoResponse for Error \{.*?\n\}\n/m, "")
    rust_guard_verdicts_in({File.join("src", "auth.rs") => own})["ContentType"]?.should be_true
  end

  # rust10x/rust-web-app keeps one `enum Error` per module of a crate.
  it "reads a variant of an enum two crate files define where the guard's file imports it" do
    mapping = <<-RUST
      pub enum Error { NoAuth }
      impl Error {
          pub fn http_status(&self) -> StatusCode {
              match self {
                  Error::NoAuth => StatusCode::UNAUTHORIZED,
              }
          }
      }
      RUST
    other = <<-RUST
      pub enum Error { NoAuth }
      impl IntoResponse for Error {
          fn into_response(self) -> Response {
              match self {
                  Error::NoAuth => StatusCode::BAD_REQUEST.into_response(),
              }
          }
      }
      RUST
    guard = <<-RUST
      use crate::error::{Error, Result};
      impl<S> FromRequestParts<S> for User {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Error> {
              parts.extensions.get::<User>().cloned().ok_or(Error::NoAuth)
          }
      }
      RUST
    error_rs = File.join("src", "error.rs")
    guard_rs = File.join("src", "middleware", "guard.rs")
    rpc_rs = File.join("src", "rpc_error.rs")
    verdicts = ->(files : Hash(String, String)) { rust_guard_verdicts_in(files)["User"]? }

    # Imported from the 401 mapping, or from the 400 one.
    verdicts.call({error_rs => mapping, rpc_rs => other, guard_rs => guard}).should be_true
    verdicts.call({error_rs => other, rpc_rs => mapping, guard_rs => guard}).should_not be_true

    # Not imported: the only defining file that maps the enum decides.
    unimported = guard.sub("use crate::error::{Error, Result};\n", "")
    verdicts.call({error_rs => mapping, rpc_rs => "pub enum Error { Rpc(String) }", guard_rs => unimported}).should be_true
    # Both map it: nothing decides.
    verdicts.call({error_rs => mapping, rpc_rs => other, guard_rs => unimported}).should_not be_true
    # An `enum Error` in a comment defines nothing.
    verdicts.call({error_rs => mapping, rpc_rs => "//! wraps the crate's enum Error for logging", guard_rs => unimported}).should be_true
  end

  it "does not read a failed-login redirect with an error query as a refusal" do
    source = <<-RUST
      impl IntoResponse for AppError {
          fn into_response(self) -> Response {
              match self {
                  AppError::OAuthFailed => (StatusCode::FOUND, [(header::LOCATION, "/login?error=oauth")]).into_response(),
                  AppError::NoSession => (StatusCode::FOUND, [("Location", "/auth/signin?next=/")]).into_response(),
              }
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for CallbackCode {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
              parts.uri.query().map(|q| CallbackCode(q.to_string())).ok_or(AppError::OAuthFailed)
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for Session {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<Session>().cloned().ok_or(AppError::NoSession)
          }
      }
      RUST
    verdicts = rust_guard_verdicts(source)
    verdicts["CallbackCode"]?.should_not be_true
    verdicts["Session"]?.should be_true
  end

  it "reads a redirect to a login page as a refusal, and no other redirect" do
    source = <<-RUST
      impl AppError {
          fn status_code(&self) -> StatusCode {
              match self {
                  Self::NotLoggedIn => StatusCode::UNAUTHORIZED,
                  Self::Moved => StatusCode::UNAUTHORIZED,
                  Self::Internal => StatusCode::INTERNAL_SERVER_ERROR,
              }
          }
      }
      impl IntoResponse for AppError {
          fn into_response(self) -> Response {
              match self {
                  Self::NotLoggedIn => (StatusCode::SEE_OTHER, [(header::LOCATION, "/login")]).into_response(),
                  Self::Moved => Redirect::permanent("/docs/v2").into_response(),
                  other => (other.status_code(), "err").into_response(),
              }
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for User {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<u64>().map(|id| User(*id)).ok_or(AppError::NotLoggedIn)
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for Legacy {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<u64>().map(|_| Legacy).ok_or(AppError::Moved)
          }
      }
      RUST
    verdicts = rust_guard_verdicts(source)
    verdicts["User"]?.should be_true
    verdicts["Legacy"]?.should_not be_true
  end

  it "reads a struct variant built as the error" do
    source = <<-RUST
      impl IntoResponse for ApiError {
          fn into_response(self) -> Response {
              match self {
                  Self::Unauthorized { reason } => (axum::http::StatusCode::UNAUTHORIZED, reason).into_response(),
                  ApiError::Bad { .. } => (StatusCode::BAD_REQUEST, "x").into_response(),
                  ApiError::Teapot => (StatusCode::from_u16(401).unwrap(), "x").into_response(),
              }
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for A {
          type Rejection = ApiError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<u64>().map(|_| A).ok_or(ApiError::Unauthorized { reason: "x".into() })
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for D {
          type Rejection = ApiError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<u64>().map(|_| D).ok_or(ApiError::Bad { field: ApiError::Unauthorized { reason: "x".into() } })
          }
      }
      impl<S: Send + Sync> FromRequestParts<S> for T {
          type Rejection = ApiError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
              parts.extensions.get::<u64>().map(|_| T).ok_or(ApiError::Teapot)
          }
      }
      RUST
    verdicts = rust_guard_verdicts(source)
    verdicts["A"]?.should be_true
    verdicts["D"]?.should_not be_true
    verdicts["T"]?.should_not be_true
  end
end
