require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

describe "Detect Rust Warp" do
  options = create_test_options
  instance = Detector::Rust::Warp.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nwarp = {}").should eq(true)
  end
end
