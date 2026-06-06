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

  it "rejects IngressClass manifests" do
    src = <<-YAML
      apiVersion: networking.k8s.io/v1
      kind: IngressClass
      metadata:
        name: nginx
      YAML

    instance.detect("ingressclass.yaml", src).should be_false
  end

  it "rejects values files that mention ingress examples" do
    src = <<-YAML
      ingress:
        enabled: true
        example:
          apiVersion: networking.k8s.io/v1
          kind: Ingress
      YAML

    instance.detect("values.yaml", src).should be_false
  end

  it "detects templated Helm Ingress manifests" do
    locator = CodeLocator.instance
    locator.clear "k8s-ingress-spec"

    src = <<-YAML
      {{- if .Values.ingress.enabled }}
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: {{ include "app.fullname" . }}
      spec:
        rules:
          - host: {{ .Values.ingress.host }}
            http:
              paths:
                - path: {{ .Values.ingress.path }}
                  pathType: {{ default "Prefix" .Values.ingress.pathType }}
      {{- end }}
      YAML

    instance.detect("templates/ingress.yaml", src).should be_true
    locator.all("k8s-ingress-spec").should eq ["templates/ingress.yaml"]
  end

  it "detects legacy extensions v1beta1 Ingress manifests" do
    src = <<-YAML
      apiVersion: extensions/v1beta1
      kind: Ingress
      metadata:
        name: legacy
      YAML

    instance.detect("legacy-ingress.yaml", src).should be_true
  end

  it "detects Ingress manifests inside Kubernetes List items" do
    src = <<-YAML
      apiVersion: v1
      kind: List
      items:
        - apiVersion: networking.k8s.io/v1
          kind: Ingress
          metadata:
            name: listed
      YAML

    instance.detect("list.yaml", src).should be_true
  end
end
