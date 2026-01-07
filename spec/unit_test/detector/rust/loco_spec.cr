require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/loco"

describe "Detect Rust Loco" do
  options = create_test_options
  instance = Detector::Rust::Loco.new options

  it "Cargo.toml with loco-rs dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nloco-rs = { version = \"0.2\" }").should be_true
  end

  it "Cargo.toml with loco-rs simple dependency" do
    instance.detect("Cargo.toml", "[dependencies]\nloco-rs = \"0.2\"").should be_true
  end

  it "should not detect non-Cargo.toml files" do
    instance.detect("package.json", "loco-rs").should be_false
  end

  it "should not detect Cargo.toml without loco-rs" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = \"0.7\"").should be_false
  end
end
