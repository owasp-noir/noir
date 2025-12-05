require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Axum" do
  options = create_test_options
  instance = Detector::Rust::Axum.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = {}").should eq(true)
  end
end
