require "../../../src/detector/detectors/*"

describe "Detect Crystal Lucky" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorCrystalLucky.new options

  it "shard.yml" do
    instance.detect("shard.yml", "luckyframework/lucky").should eq(true)
  end
end
