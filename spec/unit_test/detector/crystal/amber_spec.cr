require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Amber" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Crystal::Amber.new options

  it "shard.yml" do
    instance.detect("shard.yml", "amberframework/amber").should eq(true)
  end
end