require "../../../src/detector/detectors/*"

describe "Detect Rust Axum" do
  options = default_options()
  instance = DetectorRustAxum.new options

  it "Gargo.toml" do
    instance.detect("Cargo.toml", "[dependencies]\naxum = {}").should eq(true)
  end
end
