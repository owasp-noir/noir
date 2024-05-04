require "../../../src/detector/detectors/*"

describe "Detect Rust Rocket" do
  options = default_options()
  instance = DetectorRustRocket.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\nrocket = {}").should eq(true)
  end
end
