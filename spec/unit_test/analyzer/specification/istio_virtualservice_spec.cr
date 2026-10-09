require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/istio_virtualservice"

private def analyze_vs(content : String)
  path = File.tempname("virtualservice", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC
  locator.push Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC, path

  options = create_test_options
  analyzer = Analyzer::Specification::IstioVirtualservice.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Istio VirtualService Analyzer" do
  it "extracts uri matches with method" do
    endpoints = analyze_vs <<-YAML
      apiVersion: networking.istio.io/v1
      kind: VirtualService
      metadata: {name: api-vs}
      spec:
        hosts: ["api.example.com"]
        http:
          - match:
              - uri: {prefix: /v1/users}
                method: {exact: GET}
              - uri: {exact: /v1/users}
                method: {exact: POST}
      YAML

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/v1/users", "GET"},
      {"/v1/users", "POST"},
    ])
    endpoints.each { |e| tag_descriptions(e, "virtualservice-host").should eq ["api.example.com"] }
  end

  it "emits rewrite uri as additional endpoint" do
    endpoints = analyze_vs <<-YAML
      apiVersion: networking.istio.io/v1
      kind: VirtualService
      metadata: {name: vs}
      spec:
        http:
          - match:
              - uri: {regex: "/v2/.*"}
            rewrite: {uri: /v1/}
      YAML

    endpoints.map(&.url).sort!.should eq ["/v1/", "/v2/.*"]
    rewritten = endpoints.find!(&.url.==("/v1/"))
    tag_descriptions(rewritten, "virtualservice-source").should eq ["rewrite"]
    regex = endpoints.find!(&.url.==("/v2/.*"))
    tag_descriptions(regex, "virtualservice-path-type").should eq ["regex"]
  end

  it "defaults method to ANY when not declared" do
    endpoints = analyze_vs <<-YAML
      apiVersion: networking.istio.io/v1
      kind: VirtualService
      metadata: {name: vs}
      spec:
        http:
          - match:
              - uri: {prefix: /open}
      YAML

    endpoints.size.should eq 1
    endpoints[0].method.should eq "ANY"
  end

  # A Helm chart's manifest is a Go template, not YAML; it used to yield
  # nothing and no error. Templated values read as unknown and are dropped.
  it "reads a Helm-templated manifest" do
    endpoints = analyze_vs <<-YAML
      {{- if .Values.istio.enabled }}
      apiVersion: networking.istio.io/v1beta1
      kind: VirtualService
      metadata:
        name: {{ include "app.fullname" . }}
      spec:
        hosts:
          - api.example.com
          - {{ .Values.extraHost }}
        http:
          - match:
              - uri:
                  prefix: /api/v1
                method:
                  exact: POST
              - uri:
                  prefix: {{ .Values.basePath }}/v2
            route:
              - destination:
                  host: {{ .Values.service.name }}
      {{- end }}
      YAML

    endpoints.map { |e| {e.url, e.method} }.should eq([{"/api/v1", "POST"}])
    endpoints.flat_map { |e| tag_descriptions(e, "virtualservice-host") }.should eq(["api.example.com"])
  end
end
