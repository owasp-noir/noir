require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect WSDL" do
  options = create_test_options
  instance = Detector::Specification::WSDL.new options

  it "wsdl extension with wsdl:definitions" do
    sample = %(<?xml version="1.0"?><wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"></wsdl:definitions>)
    instance.detect("service.wsdl", sample).should be_true
  end

  it "rejects unrelated xml" do
    instance.detect("settings.xml", "<config><items/></config>").should be_false
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "wsdl-spec"
    sample = %(<?xml version="1.0"?><wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"></wsdl:definitions>)
    instance.detect("service.wsdl", sample)
    locator.all("wsdl-spec").should eq(["service.wsdl"])
  end
end
