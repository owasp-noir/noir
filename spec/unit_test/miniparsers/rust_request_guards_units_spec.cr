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

  it "finds handler body calls of refusing inherent methods on a parameter" do
    source = <<-RUST
      pub type ReqPrincipal = web::ReqData<Principal>;
      impl Principal {
          pub fn validate_session(&self) -> Result<&Session, ErrorResponse> {
              match &self.session {
                  Some(s) => Ok(s),
                  None => Err(ErrorResponse::new(ErrorResponseType::Unauthorized, "no session")),
              }
          }
          pub fn validate_admin_session(&self) -> Result<(), ErrorResponse> {
              self.validate_session()?;
              Ok(())
          }
          pub fn validate_either(&self) -> Result<(), ErrorResponse> {
              if self.is_admin() {
                  return self.validate_admin_session();
              }
              self.validate_session().map(|_| ())
          }
          pub fn validate_noop(&self) -> Result<(), ErrorResponse> {
              Ok(())
          }
          pub fn validate_csrf(&self) -> Result<(), ErrorResponse> {
              Err(ErrorResponse::new(ErrorResponseType::Forbidden, "csrf"))
          }
          pub fn is_admin(&self) -> bool { false }
      }
      pub async fn guarded(principal: ReqPrincipal) -> Result<HttpResponse> {
          principal.validate_admin_session()?;
          Ok(ok())
      }
      pub async fn csrf_only(principal: ReqPrincipal) -> Result<HttpResponse> {
          principal.validate_csrf()?;
          Ok(ok())
      }
      pub async fn branchy(principal: ReqPrincipal, flag: bool) -> Result<HttpResponse> {
          if flag {
              principal.validate_session()?;
          }
          Ok(ok())
      }
      pub async fn both_arms(principal: ReqPrincipal) -> Result<HttpResponse> {
          if principal.is_admin() {
              principal.validate_admin_session()?;
          } else {
              principal.validate_session()?;
          }
          Ok(ok())
      }
      pub async fn one_arm(principal: ReqPrincipal) -> Result<HttpResponse> {
          if principal.is_admin() {
              principal.validate_admin_session()?;
          } else {
              log();
          }
          Ok(ok())
      }
      pub async fn plain(principal: ReqPrincipal) -> Result<HttpResponse> {
          let admin = principal.is_admin();
          Ok(ok())
      }
      RUST
    facts = Noir::RustRequestGuards::Facts.new
    Noir::RustRequestGuards.scan(source, facts)
    Noir::RustRequestGuards.resolve(facts)
    facts.refusing_units.should contain("Principal::validate_session")
    facts.refusing_units.should contain("Principal::validate_admin_session")
    facts.refusing_units.should contain("Principal::validate_either")
    facts.refusing_units.should_not contain("Principal::validate_noop")
    facts.refusing_units.should_not contain("Principal::validate_csrf")
    facts.refusing_units.should_not contain("Principal::is_admin")

    calls = Noir::RustRequestGuards.handler_guard_calls(source) do |type_text, method|
      Noir::RustRequestGuards.type_names(type_text, facts).map { |type| "#{type}::#{method}" }.find { |label| facts.refusing_units.includes?(label) }
    end
    calls.values.should eq(["Principal::validate_admin_session", "Principal::validate_session"])
  end
end
