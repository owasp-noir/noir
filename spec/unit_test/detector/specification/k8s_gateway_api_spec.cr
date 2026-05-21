require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Kubernetes Gateway API manifests" do
  options = create_test_options
  instance = Detector::Specification::K8sGatewayApi.new options

  httproute = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: api-route
    spec:
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /v1/users
    YAML

  it "detects HTTPRoute manifest" do
    locator = CodeLocator.instance
    locator.clear "k8s-gateway-api-spec"

    instance.detect("routes/api.yaml", httproute).should be_true
    locator.all("k8s-gateway-api-spec").should eq ["routes/api.yaml"]
  end

  it "rejects non-HTTPRoute resources" do
    src = <<-YAML
      apiVersion: gateway.networking.k8s.io/v1
      kind: Gateway
      YAML
    instance.detect("gateway.yaml", src).should be_false
  end
end
