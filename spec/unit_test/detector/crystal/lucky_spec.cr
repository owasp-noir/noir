require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Lucky" do
  options = create_test_options
  instance = Detector::Crystal::Lucky.new options

  it "shard.yml" do
    instance.detect("shard.yml", "luckyframework/lucky").should be_true
  end
end
