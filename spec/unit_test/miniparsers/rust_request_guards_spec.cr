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
end
