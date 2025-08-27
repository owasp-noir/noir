require "../../../spec_helper"
require "../../../../src/detector/detectors/*"

describe "Detect Rust Tide" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Tide.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\ntide = {}").should eq(true)
  end
end
