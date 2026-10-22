require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"
require "../../../../src/models/skipped_files"

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
    locator.clear Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC

    instance.detect("mesh/api.yaml", vs).should be_true
    locator.all(Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC).should eq ["mesh/api.yaml"]
  end

  it "detects a VirtualService manifest with a quoted kind" do
    src = vs.sub("kind: VirtualService", %(kind: "VirtualService"))
    instance.detect("mesh/quoted.yaml", src).should be_true
  end

  it "rejects non-VirtualService Istio resources" do
    src = <<-YAML
      apiVersion: networking.istio.io/v1
      kind: DestinationRule
      YAML
    instance.detect("dr.yaml", src).should be_false
  end

  it "rejects invalid yaml that carries both markers" do
    src = "apiVersion: networking.istio.io/v1\nkind: VirtualService\nspec: [broken"
    instance.detect("broken.yaml", src).should be_false
  end

  # Helm chart `templates/` manifests failed the strict parse and were
  # dropped with no endpoint and no error.
  it "detects a Helm-templated manifest" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC
    template = <<-YAML
      {{- if .Values.enabled }}
      apiVersion: networking.istio.io/v1
      kind: VirtualService
      spec:
        hosts: ["{{ .Values.host }}"]
        http:
          - match:
              - uri:
                  prefix: /v1
      {{- end }}
      YAML

    instance.detect("chart/templates/route.yaml", template).should be_true
    locator.all(Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC).should eq ["chart/templates/route.yaml"]
  end

  it "records a manifest that still does not parse" do
    Noir::SkippedFiles.clear
    broken = <<-YAML
      apiVersion: networking.istio.io/v1
      kind: VirtualService
      spec:
        hosts: ["{{ .Values.host }}"]
        http:
          - match:
              - uri:
                  prefix: /v1
      {{ .Values.extraKey }}: [unclosed
      YAML

    instance.detect("chart/templates/broken.yaml", broken).should be_false
    Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan).map(&.message).join.should contain("broken.yaml")
  ensure
    Noir::SkippedFiles.clear
  end
end
