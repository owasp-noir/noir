require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/k8s_ingress"

private def analyze_ingress(content : String)
  path = File.tempname("ingress", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "k8s-ingress-spec"
  locator.push "k8s-ingress-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::K8sIngress.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Kubernetes Ingress Analyzer" do
  it "extracts each path under spec.rules[].http.paths" do
    endpoints = analyze_ingress <<-YAML
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
                - path: /v1/users/.*
                  pathType: ImplementationSpecific
      YAML

    endpoints.map(&.url).sort!.should eq ["/v1/users", "/v1/users/.*"]
    endpoints.each do |e|
      e.method.should eq "ANY"
      tag_descriptions(e, "ingress-host").should eq ["api.example.com"]
    end
  end

  it "marks endpoints with TLS hosts as https" do
    endpoints = analyze_ingress <<-YAML
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata: {name: tls-ingress}
      spec:
        tls:
          - hosts: ["secure.example.com"]
            secretName: tls-secret
        rules:
          - host: secure.example.com
            http:
              paths:
                - path: /admin
                  pathType: Prefix
      YAML

    endpoints.size.should eq 1
    endpoints[0].protocol.should eq "https"
  end

  it "handles multi-document YAML" do
    endpoints = analyze_ingress <<-YAML
      apiVersion: v1
      kind: Service
      metadata: {name: users}
      ---
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata: {name: ing}
      spec:
        rules:
          - http:
              paths:
                - path: /probe
                  pathType: Exact
      YAML
    endpoints.size.should eq 1
    endpoints[0].url.should eq "/probe"
    tag_descriptions(endpoints[0], "ingress-path-type").should eq ["exact"]
  end
end
