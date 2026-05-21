require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Kubernetes Ingress manifests" do
  options = create_test_options
  instance = Detector::Specification::K8sIngress.new options

  ingress = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: api-ingress
    spec:
      rules:
        - host: api.example.com
          http:
            paths:
              - path: /v1/users
                pathType: Prefix
    YAML

  it "detects networking.k8s.io Ingress YAML" do
    locator = CodeLocator.instance
    locator.clear "k8s-ingress-spec"

    instance.detect("manifests/ingress.yaml", ingress).should be_true
    locator.all("k8s-ingress-spec").should eq ["manifests/ingress.yaml"]
  end

  it "rejects non-Ingress YAML" do
    src = <<-YAML
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      YAML
    instance.detect("policy.yaml", src).should be_false
  end

  it "ignores unrelated extensions" do
    instance.detect("ingress.json", ingress).should be_false
  end
end
