require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Salvo" do
  options = create_test_options
  instance = Detector::Rust::Salvo.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nsalvo = { version = \"0.68\" }").should be_true
  end

  it "Cargo.toml - not salvo" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = {}").should be_false
  end

  it "not Cargo.toml" do
    instance.detect("main.rs", "use salvo::prelude::*;").should be_false
  end
end
