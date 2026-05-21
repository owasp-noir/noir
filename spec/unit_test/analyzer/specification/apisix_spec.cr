require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/apisix"

private def analyze_apisix(yaml_content : String? = nil, json_content : String? = nil) : Array(Endpoint)
  locator = CodeLocator.instance
  locator.clear "apisix-yaml"
  locator.clear "apisix-json"

  yaml_path = nil
  json_path = nil

  if yaml_content
    yaml_path = File.tempname("apisix", ".yaml")
    File.write(yaml_path, yaml_content)
    locator.push "apisix-yaml", yaml_path
  end

  if json_content
    json_path = File.tempname("apisix", ".json")
    File.write(json_path, json_content)
    locator.push "apisix-json", json_path
  end

  analyzer = Analyzer::Specification::Apisix.new(create_test_options)
  analyzer.analyze
ensure
  File.delete(yaml_path) if yaml_path && File.exists?(yaml_path)
  File.delete(json_path) if json_path && File.exists?(json_path)
end

describe "Apisix Analyzer" do
  it "extracts uri/uris and methods including wildcard ANY" do
    yaml = <<-YAML
      routes:
        - uri: /v1/users
          methods: [GET, POST]
          upstream_id: 1
        - uris: [/admin, /admin/*]
          methods: ["*"]
          plugins:
            key-auth: {}
      YAML

    endpoints = analyze_apisix(yaml_content: yaml)
    endpoints.map { |ep| {ep.url, ep.method} }.sort!.should eq([
      {"/admin", "ANY"},
      {"/admin/*", "ANY"},
      {"/v1/users", "GET"},
      {"/v1/users", "POST"},
    ])
  end

  it "captures all hosts from hosts[] and host as Host header params" do
    yaml = <<-YAML
      routes:
        - uri: /internal
          methods: [DELETE]
          hosts: [api.example.com, internal.example.com]
          upstream_id: 2
        - uri: /admin
          methods: [GET]
          host: admin.example.com
          plugins:
            cors: {}
      YAML

    endpoints = analyze_apisix(yaml_content: yaml)
    internal = endpoints.find { |ep| ep.url == "/internal" && ep.method == "DELETE" }
    raise "expected /internal DELETE endpoint" unless internal
    internal_hosts = internal.params.select { |p| p.name == "Host" && p.param_type == "header" }.map(&.value).sort!
    internal_hosts.should eq(["api.example.com", "internal.example.com"])

    admin = endpoints.find { |ep| ep.url == "/admin" && ep.method == "GET" }
    raise "expected /admin GET endpoint" unless admin
    admin_hosts = admin.params.select { |p| p.name == "Host" && p.param_type == "header" }.map(&.value)
    admin_hosts.should eq(["admin.example.com"])
  end

  it "handles APISIX JSON route documents" do
    json = <<-JSON
      {
        "routes": [
          {
            "uri": "/json/users",
            "methods": ["GET"],
            "upstream_id": 10
          }
        ]
      }
      JSON

    endpoints = analyze_apisix(json_content: json)
    endpoints.map { |ep| {ep.url, ep.method} }.should eq([{"/json/users", "GET"}])
  end
end
