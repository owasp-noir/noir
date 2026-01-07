require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Tide" do
  options = create_test_options
  instance = Detector::Rust::Tide.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\ntide = {}").should be_true
  end
end
