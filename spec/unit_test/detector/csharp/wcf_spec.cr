require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# WCF" do
  options = create_test_options
  instance = Detector::CSharp::Wcf.new options

  it "service contract with WebGet" do
    instance.detect("IOrderService.cs", "[OperationContract]\n[WebGet(UriTemplate = \"orders\")]\nstring Get();").should be_true
  end

  it "combined attribute section with WebInvoke" do
    instance.detect("IOrderService.cs", "[OperationContract, WebInvoke(Method = \"PUT\")]\nvoid Put();").should be_true
  end

  it "SOAP-only contract" do
    instance.detect("IOrderService.cs", "[ServiceContract]\ninterface I { [OperationContract] string Get(); }").should be_false
  end

  it "WebGet outside a service contract" do
    instance.detect("Client.cs", "var x = new WebGet();").should be_false
  end
end
