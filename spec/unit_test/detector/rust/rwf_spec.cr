require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust RWF" do
  options = create_test_options
  instance = Detector::Rust::Rwf.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nrwf = {}").should eq(true)
  end
end
