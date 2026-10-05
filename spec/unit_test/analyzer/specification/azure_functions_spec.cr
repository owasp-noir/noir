require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/azure_functions"

private def analyze_azure(content : String, function_dir = "MyFunc", host_json : String? = nil)
  dir = File.tempname("azure_function")
  Dir.mkdir_p(File.join(dir, function_dir))
  path = File.join(dir, function_dir, "function.json")
  File.write(path, content)
  host_path = File.join(dir, "host.json")
  File.write(host_path, host_json) if host_json
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC
  locator.push Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC, path

  options = create_test_options
  analyzer = Analyzer::Specification::AzureFunctions.new options
  analyzer.analyze
ensure
  if dir
    File.delete(path) if path && File.exists?(path)
    File.delete(host_path) if host_path && File.exists?(host_path)
    Dir.delete(File.join(dir, function_dir)) if Dir.exists?(File.join(dir, function_dir))
    Dir.delete(dir) if Dir.exists?(dir)
  end
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Azure Functions Analyzer" do
  it "extracts httpTrigger methods + route" do
    endpoints = analyze_azure(<<-JSON, "Users")
      {
        "bindings": [
          {
            "type": "httpTrigger",
            "direction": "in",
            "name": "req",
            "methods": ["get", "post"],
            "route": "users/{id?}",
            "authLevel": "function"
          }
        ]
      }
      JSON

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/api/users/{id?}", "GET"},
      {"/api/users/{id?}", "POST"},
    ])
    endpoints.each { |e| tag_descriptions(e, "azure-auth-level").should eq ["function"] }
  end

  it "falls back to function folder name when route is absent" do
    endpoints = analyze_azure(<<-JSON, "Healthcheck")
      {
        "bindings": [
          {"type": "httpTrigger", "methods": ["get"]}
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/api/Healthcheck"
    endpoints[0].method.should eq "GET"
  end

  it "honours a routePrefix override in host.json" do
    endpoints = analyze_azure(<<-JSON, "Users", %({"version":"2.0","extensions":{"http":{"routePrefix":"gateway"}}}))
      {
        "bindings": [
          {"type": "httpTrigger", "methods": ["get"], "route": "users"}
        ]
      }
      JSON

    endpoints.map(&.url).should eq ["/gateway/users"]
  end

  it "drops the prefix entirely when host.json sets routePrefix to an empty string" do
    endpoints = analyze_azure(<<-JSON, "Users", %({"extensions":{"http":{"routePrefix":""}}}))
      {
        "bindings": [
          {"type": "httpTrigger", "methods": ["get"], "route": "users"}
        ]
      }
      JSON

    endpoints.map(&.url).should eq ["/users"]
  end

  it "defaults method to ANY when methods are not declared" do
    endpoints = analyze_azure(<<-JSON, "AnyFunc")
      {
        "bindings": [
          {"type": "httpTrigger", "route": "any"}
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoints[0].method.should eq "ANY"
  end
end

describe "Azure Functions Analyzer (code-first)" do
  it "takes the prefix from the nearest host.json without leaving the scan base" do
    outer = File.tempname("azure_outer")
    project = File.join(outer, "proj")
    Dir.mkdir_p(File.join(project, "src"))
    File.write(File.join(outer, "host.json"), %({"extensions":{"http":{"routePrefix":"unrelated"}}}))
    source = File.join(project, "src", "a.js")
    File.write(source, %(const { app } = require("@azure/functions");\napp.http("users", { methods: ["GET", "POST"], route: "users", handler });\n))

    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC
    locator.push Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC, source

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(project)])
    endpoints = Analyzer::Specification::AzureFunctions.new(options).analyze

    endpoints.map { |e| {e.url, e.method} }.should eq [{"/api/users", "GET"}, {"/api/users", "POST"}]
    endpoints.map(&.details.code_paths.first.line).should eq [2, 2]
    # Each endpoint owns its code_paths, so a merge into one cannot leak.
    endpoints[0].details.code_paths.should_not be(endpoints[1].details.code_paths)
  ensure
    FileUtils.rm_rf(outer) if outer
  end
end
