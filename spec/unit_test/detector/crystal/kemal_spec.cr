require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal Kemal" do
  options = create_test_options
  instance = Detector::Crystal::Kemal.new options

  it "shard.yml" do
    instance.detect("shard.yml", "kemalcr/kemal").should be_true
  end
end
