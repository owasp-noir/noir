require "../../../spec_helper"
require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Phoenix" do
  options = create_test_options
  instance = Detector::Elixir::Phoenix.new options

  it "mix" do
    instance.detect("mix.exs", "ElixirPhoenix").should eq(true)
  end
end
