require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Grip" do
  options = create_test_options
  instance = Detector::Crystal::Grip.new options

  it "shard.yml" do
    instance.detect("shard.yml", "grip-framework/grip").should eq(true)
  end
end
