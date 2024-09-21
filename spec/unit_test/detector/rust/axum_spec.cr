require "../../../../src/detector/detectors/*"

describe "Detect Rust Axum" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Rust::Axum.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = {}").should eq(true)
  end
end
