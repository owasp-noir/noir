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
    locator.clear Noir::LocatorKeys::K8S_GATEWAY_API_SPEC

    instance.detect("routes/api.yaml", httproute).should be_true
    locator.all(Noir::LocatorKeys::K8S_GATEWAY_API_SPEC).should eq ["routes/api.yaml"]
  end

  it "detects an HTTPRoute manifest with a quoted kind" do
    src = httproute.sub("kind: HTTPRoute", %(kind: "HTTPRoute"))
    instance.detect("routes/quoted.yaml", src).should be_true
  end

  it "rejects non-HTTPRoute resources" do
    src = <<-YAML
      apiVersion: gateway.networking.k8s.io/v1
      kind: Gateway
      YAML
    instance.detect("gateway.yaml", src).should be_false
  end

  it "rejects invalid yaml that carries both markers" do
    src = "apiVersion: gateway.networking.k8s.io/v1\nkind: HTTPRoute\nspec: [broken"
    instance.detect("broken.yaml", src).should be_false
  end
end
