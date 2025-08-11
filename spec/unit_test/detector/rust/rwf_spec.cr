require "../../../../src/detector/detectors/*"

describe "Detect Rust RWF" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Rwf.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nrwf = {}").should eq(true)
  end
end