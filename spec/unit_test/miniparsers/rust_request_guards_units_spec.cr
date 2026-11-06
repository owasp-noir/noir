require "../../spec_helper"
require "../../../src/miniparsers/rust_request_guards"

describe Noir::RustRequestGuards do
  it "reads a refusal built by a constructor fn and one delegated to a free helper" do
    source = <<-RUST
      pub async fn bearer(parts: &mut Parts, state: &AppState) -> Result<Perms> {
          let h = Header::from_request_parts(parts, state).await
              .map_err(|_| HttpError::unauthorized(None, None))?;
          Ok(Perms)
      }
      pub async fn peek(parts: &mut Parts) -> Result<Perms> { Ok(Perms) }
      pub struct Org;
      impl FromRequestParts<AppState> for Org {
          async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self> {
              let p = bearer(parts, state).await?;
              Ok(Org)
          }
      }
      pub struct Lax;
      impl FromRequestParts<AppState> for Lax {
          async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self> {
              let p = peek(parts).await?;
              if let Ok(x) = bearer(parts, state).await { return Ok(Lax); }
              Ok(Lax)
          }
      }
      RUST
    facts = Noir::RustRequestGuards::Facts.new
    Noir::RustRequestGuards.scan(source, facts)
    verdicts = Noir::RustRequestGuards.resolve(facts)
    verdicts["Org"]?.should be_true
    verdicts["Lax"]?.should be_false
  end

  it "does not read look-alike text, and scopes free helpers to their crate" do
    a = <<-RUST
      pub async fn check(parts: &mut Parts) -> Result<(), E> {
          Err(HttpError::forbidden())
      }
      pub async fn soft(parts: &mut Parts) -> Result<(), E> {
          // HttpError::forbidden()
          let msg = "HttpError::unauthorized";
          Ok(())
      }
      pub struct Org;
      impl FromRequestParts<S> for Org {
          async fn from_request_parts(parts: &mut Parts, s: &S) -> Result<Self> {
              check(parts).await?;
              Ok(Org)
          }
      }
      pub struct Lax;
      impl FromRequestParts<S> for Lax {
          async fn from_request_parts(parts: &mut Parts, s: &S) -> Result<Self> {
              soft(parts).await?;
              Ok(Lax)
          }
      }
      RUST
    # same name in another crate, not request-taking and not refusing
    b = <<-RUST
      pub fn check(name: &str) -> Result<(), E> { Ok(()) }
      pub struct Other;
      impl FromRequestParts<S> for Other {
          async fn from_request_parts(parts: &mut Parts, s: &S) -> Result<Self> {
              check("x")?;
              Ok(Other)
          }
      }
      RUST
    facts = Noir::RustRequestGuards::Facts.new
    Noir::RustRequestGuards.scan(a, facts, "a/src/a.rs")
    Noir::RustRequestGuards.scan(b, facts, "b/src/b.rs")
    verdicts = Noir::RustRequestGuards.resolve(facts)
    verdicts["Org"]?.should be_true
    verdicts["Lax"]?.should be_false
    verdicts["Other"]?.should be_false
  end
end
