require "../../../src/detector/detectors/*"

describe "Detect Elixir Phoenix" do
  options = default_options()
  instance = DetectorElixirPhoenix.new options

  it "mix" do
    instance.detect("mix.exs", "ElixirPhoenix").should eq(true)
  end
end
