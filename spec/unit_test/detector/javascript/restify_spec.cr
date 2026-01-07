require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Restify" do
  options = create_test_options
  instance = Detector::Javascript::Restify.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('restify')").should be_true
  end
  it "require_double_quot" do
    instance.detect("index.js", "require(\"restify\")").should be_true
  end
end
