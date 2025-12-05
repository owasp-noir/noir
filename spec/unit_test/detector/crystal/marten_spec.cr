require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Marten" do
  options = create_test_options
  instance = Detector::Crystal::Marten.new options

  it "shard.yml" do
    instance.detect("shard.yml", "martenframework/marten").should eq(true)
  end
end
