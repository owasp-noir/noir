require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Istio VirtualService manifest" do
  options = create_test_options
  instance = Detector::Specification::IstioVirtualservice.new options

  vs = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: VirtualService
    metadata:
      name: api-vs
    spec:
      hosts: ["api.example.com"]
      http:
        - match:
            - uri:
                prefix: /v1/users
              method:
                exact: GET
    YAML

  it "detects VirtualService manifest" do
    locator = CodeLocator.instance
    locator.clear "istio-virtualservice-spec"

    instance.detect("mesh/api.yaml", vs).should be_true
    locator.all("istio-virtualservice-spec").should eq ["mesh/api.yaml"]
  end

  it "rejects non-VirtualService Istio resources" do
    src = <<-YAML
      apiVersion: networking.istio.io/v1
      kind: DestinationRule
      YAML
    instance.detect("dr.yaml", src).should be_false
  end
end
