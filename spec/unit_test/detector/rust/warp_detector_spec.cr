require "../../../../src/detector/detectors/*"

describe "Detect Rust Warp" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Warp.new options

  it "Cargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nwarp = {}").should eq(true)
  end
end
