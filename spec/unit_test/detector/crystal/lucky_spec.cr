require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Lucky" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Crystal::Lucky.new options

  it "shard.yml" do
    instance.detect("shard.yml", "luckyframework/lucky").should eq(true)
  end
end
