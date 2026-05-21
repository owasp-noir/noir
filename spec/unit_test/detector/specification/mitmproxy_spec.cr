require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/utils/tnetstring"

private def build_flow_bytes(version : Array(Tnetstring::Value) = [3_i64, 0_i64, 0_i64].map(&.as(Tnetstring::Value))) : Bytes
  request = {
    "method" => "GET".as(Tnetstring::Value),
    "host"   => "example.com".as(Tnetstring::Value),
    "scheme" => "https".as(Tnetstring::Value),
    "port"   => 443_i64.as(Tnetstring::Value),
    "path"   => "/api/users".as(Tnetstring::Value),
  } of String => Tnetstring::Value
  flow = {
    "type"    => "http".as(Tnetstring::Value),
    "version" => version.as(Tnetstring::Value),
    "request" => request.as(Tnetstring::Value),
  } of String => Tnetstring::Value
  Tnetstring.encode(flow.as(Tnetstring::Value))
end

describe "Detect mitmproxy flow" do
  options = create_test_options
  instance = Detector::Specification::Mitmproxy.new options

  it "detects a flow file with the type marker" do
    content = String.new(build_flow_bytes)
    instance.detect("capture.mitm", content).should be_true
  end

  it "ignores files without the tnetstring length prefix" do
    instance.detect("capture.mitm", "not a flow").should be_false
  end

  it "ignores files whose extension does not match" do
    content = String.new(build_flow_bytes)
    instance.detect("capture.txt", content).should be_false
  end

  it "registers the path in CodeLocator on a match" do
    locator = CodeLocator.instance
    locator.clear "mitmproxy-path"
    content = String.new(build_flow_bytes)
    instance.detect("flows/recon.flow", content)
    locator.all("mitmproxy-path").should eq ["flows/recon.flow"]
  end
end
