require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Kemal" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Crystal::Kemal.new options

  it "shard.yml" do
    instance.detect("shard.yml", "kemalcr/kemal").should eq(true)
  end
end
