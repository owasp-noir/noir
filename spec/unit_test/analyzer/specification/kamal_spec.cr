require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/kamal"

private def analyze_kamal(content : String)
  path = File.tempname("deploy", ".yml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "kamal-spec"
  locator.push "kamal-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::Kamal.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Kamal Analyzer" do
  it "extracts the app root and the health endpoint from the proxy block" do
    endpoints = analyze_kamal <<-YAML
      service: my-app
      image: acme/my-app
      proxy:
        ssl: true
        host: app.example.com
        app_port: 3000
        healthcheck:
          path: /up
      YAML

    endpoints.map { |e| "#{e.method} #{e.url}" }.sort!.should eq ["ANY /", "GET /up"]
    endpoints.each do |e|
      e.protocol.should eq "https"
      tag_descriptions(e, "kamal-host").should eq ["app.example.com"]
      tag_descriptions(e, "kamal-service").should eq ["my-app"]
      tag_descriptions(e, "kamal-app-port").should eq ["3000"]
    end
  end

  it "defaults the health endpoint to /up when none is configured" do
    endpoints = analyze_kamal <<-YAML
      service: my-app
      image: acme/my-app
      proxy:
        host: app.example.com
      YAML

    health = endpoints.find! { |e| e.method == "GET" }
    health.url.should eq "/up"
    health.protocol.should eq "http"
    tag_descriptions(health, "kamal-source").should eq ["healthcheck"]
  end

  it "emits one endpoint per path prefix and folds multiple hosts into one tag" do
    endpoints = analyze_kamal <<-YAML
      service: my-app
      image: acme/my-app
      proxy:
        ssl: true
        hosts:
          - app.example.com
          - www.example.com
        path_prefix: "/api,/oauth_callback"
      YAML

    app_routes = endpoints.select { |e| e.method == "ANY" }
    app_routes.map(&.url).sort!.should eq ["/api", "/oauth_callback"]
    app_routes.each do |e|
      tag_descriptions(e, "kamal-host").should eq ["app.example.com, www.example.com"]
    end
  end

  it "normalizes prefixes that omit the leading slash" do
    endpoints = analyze_kamal <<-YAML
      service: my-app
      image: acme/my-app
      proxy:
        host: app.example.com
        path_prefixes:
          - admin
      YAML

    endpoints.any? { |e| e.method == "ANY" && e.url == "/admin" }.should be_true
  end

  it "produces no endpoints when the config has no proxy block" do
    endpoints = analyze_kamal <<-YAML
      service: my-app
      image: acme/my-app
      servers:
        - 192.168.0.1
      YAML

    endpoints.should be_empty
  end
end
