require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Rocket" do
  options = create_test_options
  instance = Detector::Rust::Rocket.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nrocket = {}").should be_true
  end
end
