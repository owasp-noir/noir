require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/k8s_ingress"

private def analyze_ingress(content : String)
  path = File.tempname("ingress", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::K8S_INGRESS_SPEC
  locator.push Noir::LocatorKeys::K8S_INGRESS_SPEC, path

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
    endpoints.sort_by(&.url).map(&.details.code_paths.first.line).should eq [10, 12]
    endpoints.each do |e|
      e.method.should eq "GET"
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

  it "extracts legacy extensions v1beta1 ingress paths" do
    endpoints = analyze_ingress <<-YAML
      apiVersion: extensions/v1beta1
      kind: Ingress
      metadata: {name: legacy}
      spec:
        rules:
          - host: legacy.example.com
            http:
              paths:
                - path: /legacy
                  backend:
                    serviceName: legacy
                    servicePort: http
      YAML

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/legacy"
    tag_descriptions(endpoints[0], "ingress-host").should eq ["legacy.example.com"]
  end

  it "uses root path for defaultBackend and backend paths without explicit path" do
    endpoints = analyze_ingress <<-YAML
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata: {name: defaults}
      spec:
        defaultBackend:
          service:
            name: default-service
            port:
              number: 80
        rules:
          - http:
              paths:
                - backend:
                    service:
                      name: api
                      port:
                        number: 80
      YAML

    endpoints.map(&.url).sort!.should eq ["/", "/"]
    endpoints.map(&.method).should eq ["GET", "GET"]
    tag_descriptions(endpoints[0], "ingress-source").should eq ["default-backend"]
    tag_descriptions(endpoints[1], "ingress-source").should eq ["rule"]
  end

  it "extracts templated Helm ingress paths with safe defaults" do
    endpoints = analyze_ingress <<-YAML
      {{- if .Values.server.ingress.enabled }}
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: {{ include "argo-cd.server.fullname" . }}
      spec:
        rules:
          - host: {{ tpl (.Values.server.ingress.hostname) $ }}
            http:
              paths:
                - path: {{ .Values.server.ingress.path }}
                  pathType: {{ default "Prefix" .Values.server.ingress.pathType }}
                  backend:
                    service:
                      name: {{ include "argo-cd.server.fullname" . }}
                - path: /grpc
                  pathType: Exact
                  backend:
                    service:
                      name: grpc
      {{- end }}
      YAML

    endpoints.map(&.url).sort!.should eq ["/", "/grpc"]
    sources = endpoints.map { |e| tag_descriptions(e, "ingress-source").first }
    sources.uniq!
    sources.should eq ["template"]
    tag_descriptions(endpoints.find! { |e| e.url == "/" }, "ingress-path-type").should eq ["prefix"]
    tag_descriptions(endpoints.find! { |e| e.url == "/grpc" }, "ingress-path-type").should eq ["exact"]
  end

  it "extracts ingress paths from Kubernetes List items" do
    endpoints = analyze_ingress <<-YAML
      apiVersion: v1
      kind: List
      items:
        - apiVersion: networking.k8s.io/v1
          kind: Ingress
          metadata: {name: listed}
          spec:
            rules:
              - http:
                  paths:
                    - path: /listed
                      pathType: Prefix
      YAML

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/listed"
  end

  describe "auth annotations" do
    ingress = ->(annotations : String) do
      <<-YAML
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: app
          annotations:
        #{annotations}
        spec:
          defaultBackend:
            service: {name: app, port: {number: 80}}
          rules:
          - host: app.example.com
            http:
              paths:
              - path: /
                pathType: Prefix
                backend:
                  service: {name: app, port: {number: 80}}
        YAML
    end
    guards = ->(endpoints : Array(Endpoint)) do
      endpoints.flat_map { |e| e.tags.select { |t| t.name == "auth" }.map(&.description) }.uniq!
    end

    it "guards every path of an Ingress that enforces auth" do
      {
        %(    nginx.ingress.kubernetes.io/auth-url: "https://auth.example.com/check")                                                 => "Protected by ingress-nginx auth-url https://auth.example.com/check",
        "    nginx.ingress.kubernetes.io/auth-type: basic\n    nginx.ingress.kubernetes.io/auth-secret: basic-auth"                   => "Protected by ingress-nginx auth-type basic",
        %(    nginx.ingress.kubernetes.io/auth-tls-secret: default/ca)                                                                => "Protected by ingress-nginx auth-tls-verify-client on",
        "    nginx.ingress.kubernetes.io/auth-tls-secret: default/ca\n    nginx.ingress.kubernetes.io/auth-tls-verify-client: \"on\"" => "Protected by ingress-nginx auth-tls-verify-client on",
      }.each do |annotations, expected|
        endpoints = analyze_ingress(ingress.call(annotations))
        endpoints.size.should eq(2)
        endpoints.each { |e| e.tags.count(&.name.==("auth")).should eq(1) }
        guards.call(endpoints).should eq([expected])
      end
    end

    it "does not guard annotations that admit callers without credentials" do
      [
        "    nginx.ingress.kubernetes.io/auth-type: basic",
        "    nginx.ingress.kubernetes.io/auth-tls-secret: default/ca\n    nginx.ingress.kubernetes.io/auth-tls-verify-client: optional",
        "    nginx.ingress.kubernetes.io/auth-tls-secret: default/ca\n    nginx.ingress.kubernetes.io/auth-tls-verify-client: optional_no_ca",
        %(    nginx.ingress.kubernetes.io/auth-url: ""),
        "    nginx.ingress.kubernetes.io/rewrite-target: /",
      ].each do |annotations|
        guards.call(analyze_ingress(ingress.call(annotations))).should be_empty
      end
    end
  end
end
