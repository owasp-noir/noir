require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/leptos"

describe "Detect Rust Leptos" do
  options = create_test_options
  instance = Detector::Rust::Leptos.new options

  it "Cargo.toml with leptos dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nleptos = { version = \"0.8\", features = [\"fullstack\"] }").should be_true
  end

  it "Cargo.toml with workspace or table dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nleptos.workspace = true").should be_true
    instance.detect("Cargo.toml", "[dependencies.leptos]\nversion = \"0.8\"").should be_true
  end

  it "ignores companion crates and other files" do
    instance.detect("Cargo.toml", "[dependencies]\nleptos_router = \"0.8\"\nleptos-cli = \"0.8\"").should be_false
    instance.detect("main.rs", "use leptos::prelude::*;").should be_false
  end
end
