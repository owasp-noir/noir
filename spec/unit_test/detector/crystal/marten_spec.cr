require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Marten" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Crystal::Marten.new options

  it "shard.yml" do
    instance.detect("shard.yml", "martenframework/marten").should eq(true)
  end
end