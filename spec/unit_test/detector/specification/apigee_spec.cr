require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Apigee proxy endpoints" do
  options = create_test_options
  instance = Detector::Specification::Apigee.new options

  it "detects a proxy endpoint and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::APIGEE_PROXY
    content = %(<ProxyEndpoint name="default"><HTTPProxyConnection><BasePath>/v1</BasePath></HTTPProxyConnection></ProxyEndpoint>)
    instance.detect("apiproxy/proxies/default.xml", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::APIGEE_PROXY).should eq(["apiproxy/proxies/default.xml"])
  end

  it "rejects target endpoints" do
    content = %(<TargetEndpoint name="default"><HTTPTargetConnection><URL>https://x</URL></HTTPTargetConnection></TargetEndpoint>)
    instance.detect("apiproxy/targets/default.xml", content).should be_false
  end

  it "rejects unrelated XML" do
    instance.detect("pom.xml", %(<project><modelVersion>4.0.0</modelVersion></project>)).should be_false
  end
end
