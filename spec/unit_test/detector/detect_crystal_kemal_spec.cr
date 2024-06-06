require "../../../src/detector/detectors/*"

describe "Detect Crystal Kemal" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorCrystalKemal.new options

  it "shard.yml" do
    instance.detect("shard.yml", "kemalcr/kemal").should eq(true)
  end
end
