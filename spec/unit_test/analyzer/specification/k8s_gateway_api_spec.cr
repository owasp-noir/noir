require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/k8s_gateway_api"

private def analyze_gateway_api(content : String)
  path = File.tempname("httproute", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "k8s-gateway-api-spec"
  locator.push "k8s-gateway-api-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::K8sGatewayApi.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Kubernetes Gateway API Analyzer" do
  it "extracts each match with method + path" do
    endpoints = analyze_gateway_api <<-YAML
      apiVersion: gateway.networking.k8s.io/v1
      kind: HTTPRoute
      metadata: {name: api-route}
      spec:
        hostnames: ["api.example.com"]
        rules:
          - matches:
              - method: GET
                path:
                  type: PathPrefix
                  value: /v1/users
              - method: POST
                path:
                  type: Exact
                  value: /v1/users
            backendRefs: [{name: users, port: 8080}]
      YAML

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/v1/users", "GET"},
      {"/v1/users", "POST"},
    ])
    endpoints.each { |e| tag_descriptions(e, "gateway-host").should eq ["api.example.com"] }
  end

  it "supports object-shaped method matchers (exact / prefix / regex)" do
    endpoints = analyze_gateway_api <<-YAML
      apiVersion: gateway.networking.k8s.io/v1
      kind: HTTPRoute
      metadata: {name: r}
      spec:
        rules:
          - matches:
              - method: {exact: PUT}
                path: {type: PathPrefix, value: /update}
      YAML
    endpoints.size.should eq 1
    endpoints[0].method.should eq "PUT"
  end

  it "emits rewritten path as a separate tagged endpoint" do
    endpoints = analyze_gateway_api <<-YAML
      apiVersion: gateway.networking.k8s.io/v1
      kind: HTTPRoute
      metadata: {name: r}
      spec:
        rules:
          - matches:
              - path: {type: PathPrefix, value: /v2}
            filters:
              - type: URLRewrite
                urlRewrite:
                  path:
                    type: ReplaceFullPath
                    replaceFullPath: /v1
      YAML
    endpoints.map(&.url).sort!.should eq ["/v1", "/v2"]
    rewritten = endpoints.find!(&.url.==("/v1"))
    tag_descriptions(rewritten, "gateway-source").should eq ["rewrite"]
  end
end
