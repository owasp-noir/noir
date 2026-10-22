require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal HTTP::Server" do
  options = create_test_options
  instance = Detector::Crystal::Http.new options

  it "detects require http/server in .cr" do
    instance.detect("src/app.cr", %(require "http/server"\nserver = HTTP::Server.new do |ctx| end)).should be_true
  end

  it "detects HTTP::Server usage token" do
    instance.detect("handler.cr", "server = HTTP::Server.new { |context| }").should be_true
  end

  it "does not detect in non-.cr" do
    instance.detect("shard.yml", %(http/server)).should be_false
  end

  it "does not fire without signal" do
    instance.detect("other.cr", "puts hello").should be_false
  end
end
