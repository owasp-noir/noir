require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/vercel"

private def analyze_vercel_config(content : String)
  path = File.tempname("vercel", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "vercel-spec"
  locator.push "vercel-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::Vercel.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Vercel Analyzer" do
  it "extracts rewrites, redirects, routes, and headers with method ANY" do
    endpoints = analyze_vercel_config <<-JSON
      {
        "rewrites": [{"source":"/api/v1/(.*)", "destination":"/api/$1"}],
        "redirects": [{"source":"/old", "destination":"/new", "permanent": true}],
        "routes": [{"src":"^/legacy/(.*)", "dest":"/api/$1"}],
        "headers": [{"source":"/(.*)", "headers":[{"key":"x-test","value":"1"}]}]
      }
      JSON

    endpoints.map(&.url).sort!.should eq ["/(.*)", "/api/v1/(.*)", "/old", "^/legacy/(.*)"]
    endpoints.all? { |e| e.method == "ANY" }.should be_true
  end

  it "tags redirect status as 301 for permanent and 302 by default" do
    endpoints = analyze_vercel_config <<-JSON
      {
        "redirects": [
          {"source":"/moved", "destination":"/new", "permanent": true},
          {"source":"/temp", "destination":"/new-temp"}
        ]
      }
      JSON

    moved = endpoints.find!(&.url.==("/moved"))
    temp = endpoints.find!(&.url.==("/temp"))

    tag_descriptions(moved, "redirect-status").should eq ["301"]
    tag_descriptions(temp, "redirect-status").should eq ["302"]
  end

  it "supports grouped rewrite sections and marks pattern-style sources" do
    endpoints = analyze_vercel_config <<-JSON
      {
        "rewrites": {
          "beforeFiles": [{"source":"^/api/(.*)", "destination":"/api/$1"}],
          "afterFiles": [{"source":"/blog/*", "destination":"/news"}]
        }
      }
      JSON

    endpoints.map(&.url).sort!.should eq ["/blog/*", "^/api/(.*)"]
    endpoints.each do |endpoint|
      tag_descriptions(endpoint, "pattern").should eq ["vercel_source_matcher"]
    end
  end
end
