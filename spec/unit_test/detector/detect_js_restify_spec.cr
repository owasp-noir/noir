require "../../../src/detector/detectors/*"

describe "Detect JS Restify" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorJsRestify.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('restify')").should eq(true)
  end
  it "require_double_quot" do
    instance.detect("index.js", "require(\"restify\")").should eq(true)
  end
end
