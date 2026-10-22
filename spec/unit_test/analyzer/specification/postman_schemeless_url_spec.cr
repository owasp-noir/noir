require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/postman"

private def analyze_urls(*urls : String) : Array(Endpoint)
  items = urls.map { |url| %({"name": "r", "request": {"method": "GET", "url": #{url.to_json}}}) }
  content = %({"info": {"name": "Schemeless", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"}, "item": [#{items.join(",")}]})

  path = File.tempname("postman-schemeless", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::POSTMAN_JSON
  locator.push Noir::LocatorKeys::POSTMAN_JSON, path

  Analyzer::Specification::Postman.new(create_test_options).analyze
ensure
  CodeLocator.instance.clear Noir::LocatorKeys::POSTMAN_JSON
  File.delete(path) if path && File.exists?(path)
end

# A scheme-less string URL starts with its host (or a variable standing for
# it), not with a path segment: Postman reads `{{baseUrl}}/health` as host
# `{{baseUrl}}`. `URI.parse` hands such a string back whole as its "path",
# which used to keep the host as a segment (`/:baseUrl/health`) and turn the
# variable into a bogus path param.
describe "Postman scheme-less string URLs" do
  it "drops an unresolved host variable instead of making it a path segment" do
    endpoints = analyze_urls("{{baseUrl}}/users?x=1")

    endpoints.map(&.url).should eq ["/users"]
    endpoints.first.params.map { |param| {param.name, param.param_type} }.should eq [{"x", "query"}]
  end

  it "drops a literal hostname and a host with a port" do
    analyze_urls("postman-echo.com/get").map(&.url).should eq ["/get"]
    analyze_urls("localhost:3000/a/b").map(&.url).should eq ["/a/b"]
  end

  it "drops a variable scheme and host" do
    analyze_urls("{{protocol}}://{{host}}/users").map(&.url).should eq ["/users"]
  end

  it "reports no endpoint for a URL that is one runtime variable" do
    analyze_urls("{{manifestUrl}}").should be_empty
  end

  it "keeps relative and rooted paths as they are" do
    analyze_urls("users/1", "/orders").map(&.url).should eq ["/users/1", "/orders"]
  end
end
