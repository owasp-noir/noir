require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Phoenix" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Elixir::Phoenix.new options

  it "mix" do
    instance.detect("mix.exs", "ElixirPhoenix").should eq(true)
  end
end
