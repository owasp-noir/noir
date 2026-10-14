require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/bruno"

private def analyze_bru(content : String)
  path = File.tempname("bruno", ".bru")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::BRUNO_BRU
  locator.push Noir::LocatorKeys::BRUNO_BRU, path

  Analyzer::Specification::Bruno.new(create_test_options).analyze
ensure
  CodeLocator.instance.clear Noir::LocatorKeys::BRUNO_BRU
  File.delete(path) if path && File.exists?(path)
end

describe "Bruno Analyzer" do
  it "drops a {{baseUrl}} host placeholder from the path" do
    endpoints = analyze_bru <<-BRU
      put {
        url: {{baseUrl}}/users/:id?x=1
      }
      BRU

    endpoints.map(&.url).should eq(["/users/:id"])
  end

  it "keeps JSON body params next to an unquoted {{var}} value" do
    endpoints = analyze_bru <<-BRU
      post {
        url: /users
      }

      body:json {
        {
          "name": "Kim",
          "age": {{age}}
        }
      }
      BRU

    endpoints[0].params.map { |p| {p.name, p.param_type} }.should eq([{"name", "json"}, {"age", "json"}])
  end
end
