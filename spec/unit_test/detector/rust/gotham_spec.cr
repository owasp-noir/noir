require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Gotham" do
  options = create_test_options
  instance = Detector::Rust::Gotham.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\ngotham = \"0.7\"").should be_true
  end

  it "Cargo.toml with other dependencies" do
    cargo_content = <<-TOML
      [package]
      name = "my-app"
      version = "0.1.0"

      [dependencies]
      gotham = "0.7"
      serde = "1.0"
      tokio = "1.0"
      TOML
    instance.detect("Cargo.toml", cargo_content).should be_true
  end

  it "should not detect without gotham dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nrocket = \"0.5\"").should be_false
  end

  it "should not detect in non-Cargo.toml files" do
    instance.detect("main.rs", "use gotham::prelude::*;").should be_false
  end
end
