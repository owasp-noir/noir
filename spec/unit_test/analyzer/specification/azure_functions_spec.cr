require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/azure_functions"

private def analyze_azure(content : String, function_dir = "MyFunc")
  dir = File.tempname("azure_function")
  Dir.mkdir_p(File.join(dir, function_dir))
  path = File.join(dir, function_dir, "function.json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "azure-functions-spec"
  locator.push "azure-functions-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::AzureFunctions.new options
  analyzer.analyze
ensure
  if dir
    File.delete(path) if path && File.exists?(path)
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
      {"/users/{id?}", "GET"},
      {"/users/{id?}", "POST"},
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
    endpoints[0].url.should eq "/Healthcheck"
    endpoints[0].method.should eq "GET"
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
