require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/dioxus"

describe "Detect Rust Dioxus" do
  options = create_test_options
  instance = Detector::Rust::Dioxus.new options

  it "Cargo.toml with dioxus dependency" do
    instance.detect("Cargo.toml", "[dependencies]\ndioxus = { version = \"0.8\", features = [\"fullstack\"] }").should be_true
  end

  it "Cargo.toml with workspace or table dependency" do
    instance.detect("Cargo.toml", "[dependencies]\ndioxus.workspace = true").should be_true
    instance.detect("Cargo.toml", "[dependencies.dioxus]\nversion = \"0.8\"").should be_true
  end

  it "ignores companion crates and other files" do
    instance.detect("Cargo.toml", "[dependencies]\ndioxus_router = \"0.8\"\ndioxus-cli = \"0.8\"").should be_false
    instance.detect("main.rs", "use dioxus::prelude::*;").should be_false
  end
end
