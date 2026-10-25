require "../../spec_helper"
require "../../../src/miniparsers/rust_struct_fields"

describe Noir::RustStructFields do
  it "keeps a flattened field's type instead of its name" do
    source = <<-RUST
      #[derive(Deserialize)]
      pub struct Search {
          pub q: String,
          #[serde(flatten)]
          pub paging: Option<Paging>,
          #[serde(skip)]
          pub cache: u8,
      }
      RUST
    shape = Noir::RustStructFields.parse(source)["Search"]
    shape.fields.should eq(["q"])
    shape.flattened.should eq(["Option<Paging>"])
  end

  it "reads top-level structs only, never one of an inline mod" do
    source = <<-RUST
      mod legacy {
          pub struct CreateReq { pub old_name: String }
      }
      pub struct CreateReq { pub title: String }
      pub struct Empty {}
      RUST
    structs = Noir::RustStructFields.parse(source)
    structs["CreateReq"].fields.should eq(["title"])
    structs["Empty"].fields.should be_empty
  end
end
