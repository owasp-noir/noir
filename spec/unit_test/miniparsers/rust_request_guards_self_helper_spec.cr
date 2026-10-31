require "../../spec_helper"
require "../../../src/miniparsers/rust_request_guards"

describe Noir::RustRequestGuards do
  it "follows Self:: helpers of a FromRequest impl and judges an auth variant by name" do
    source = <<-RUST
      pub struct Guarded;
      impl Guarded {
          fn auth(req: &Req) -> Result<Self, AuthError> {
              match req.header("authorization") {
                  Some(_) => Ok(Guarded),
                  None => Err(AuthError::MissingAuthorizationHeader),
              }
          }
      }
      impl FromRequest for Guarded {
          fn from_request(req: &Req) -> Self::Future { ready(Self::auth(req)) }
      }
      pub struct Open;
      impl Open {
          fn find(req: &Req) -> Result<Self, AuthError> { Err(AuthError::IrretrievableState) }
      }
      impl FromRequest for Open {
          fn from_request(req: &Req) -> Self::Future { ready(Self::find(req)) }
      }
      RUST
    facts = Noir::RustRequestGuards::Facts.new
    Noir::RustRequestGuards.scan(source, facts)
    verdicts = Noir::RustRequestGuards.resolve(facts)
    verdicts["Guarded"]?.should be_true
    verdicts["Open"]?.should be_false
  end
end
