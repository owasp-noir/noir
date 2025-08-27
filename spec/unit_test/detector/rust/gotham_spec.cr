require "spec"
require "../../../../src/detector/detectors/*"
require "../../../../src/config_initializer"

describe "Detect Rust Gotham" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Gotham.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\ngotham = \"0.7\"").should eq(true)
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
    instance.detect("Cargo.toml", cargo_content).should eq(true)
  end

  it "should not detect without gotham dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nrocket = \"0.5\"").should eq(false)
  end

  it "should not detect in non-Cargo.toml files" do
    instance.detect("main.rs", "use gotham::prelude::*;").should eq(false)
  end
end