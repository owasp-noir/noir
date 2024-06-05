require "../../../src/detector/detectors/*"

describe "Detect Elixir Phoenix" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorElixirPhoenix.new options

  it "mix" do
    instance.detect("mix.exs", "ElixirPhoenix").should eq(true)
  end
end
