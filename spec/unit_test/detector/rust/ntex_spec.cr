require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust ntex" do
  options = create_test_options
  instance = Detector::Rust::Ntex.new options

  it "detects an ntex dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nntex = { version = \"2\", features = [\"tokio\"] }").should be_true
  end

  it "detects workspace and table forms" do
    instance.detect("Cargo.toml", "[dependencies]\nntex.workspace = true").should be_true
    instance.detect("Cargo.toml", "[dependencies.ntex]\nversion = \"2\"").should be_true
  end

  it "does not detect ntex sibling crates on their own" do
    instance.detect("Cargo.toml", "[dependencies]\nntex-mqtt = \"4\"\nntex-bytes = \"0.1\"").should be_false
  end

  it "does not detect actix-web" do
    instance.detect("Cargo.toml", "[dependencies]\nactix-web = \"4\"").should be_false
  end

  it "ignores Rust sources and Cargo.lock" do
    instance.detect("src/main.rs", "use ntex::web;").should be_false
    instance.detect("Cargo.lock", "[[package]]\nname = \"ntex\"\ndependencies = []").should be_false
  end
end
