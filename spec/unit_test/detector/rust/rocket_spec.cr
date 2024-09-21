require "../../../../src/detector/detectors/*"

describe "Detect Rust Rocket" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Rocket.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nrocket = {}").should eq(true)
  end
end
