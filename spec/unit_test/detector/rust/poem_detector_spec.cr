require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Poem" do
  options = create_test_options
  instance = Detector::Rust::Poem.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\npoem = { version = \"3.1\" }").should be_true
  end

  it "Cargo.toml - poem-openapi" do
    instance.detect("Cargo.toml", "[dependencies]\npoem-openapi = { version = \"5.0\" }").should be_true
  end

  it "Cargo.toml - not poem" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = {}").should be_false
  end

  it "not Cargo.toml" do
    instance.detect("main.rs", "use poem::prelude::*;").should be_false
  end
end
