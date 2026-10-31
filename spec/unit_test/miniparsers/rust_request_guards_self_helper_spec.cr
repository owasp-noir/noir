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

  it "reads handler parameter types out of a macro_rules! transcriber at absolute lines" do
    source = <<-RUST
      macro_rules! make {
          ($attr:ident) => {
              pub mod $attr {
                  pub async fn get(auth: GuardedData<P, D>, id: web::Path<String>) {}
              }
          };
      }
      RUST
    types = Noir::RustRequestGuards.handler_param_types(source)
    types[4]?.should eq ["GuardedData", "Path"]
  end

  it "keeps lines absolute when the transcriber's brace is on its own line" do
    source = "macro_rules! make {\n    ($attr:ident) =>\n    {\n        pub mod $attr {\n            pub async fn get(auth: GuardedData<P, D>) {}\n        }\n    };\n}\n"
    Noir::RustRequestGuards.handler_param_types(source)[5]?.should eq ["GuardedData"]
  end
end
