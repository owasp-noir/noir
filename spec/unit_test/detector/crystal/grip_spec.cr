require "../../../spec_helper"

describe "Detect Crystal Grip" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Crystal::Grip.new options

  it "shard.yml" do
    instance.detect("shard.yml", "grip-framework/grip").should eq(true)
  end
end
