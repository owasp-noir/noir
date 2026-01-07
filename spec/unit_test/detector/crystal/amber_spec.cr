require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Amber" do
  options = create_test_options
  instance = Detector::Crystal::Amber.new options

  it "shard.yml" do
    instance.detect("shard.yml", "amberframework/amber").should be_true
  end
end
