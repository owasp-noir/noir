require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/cloudflare_wrangler"

private def analyze_wrangler(content : String, ext = ".toml")
  path = File.tempname("wrangler", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "cloudflare-wrangler-spec"
  locator.push "cloudflare-wrangler-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::CloudflareWrangler.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Cloudflare Wrangler Analyzer" do
  it "extracts [[routes]] entries from wrangler.toml" do
    endpoints = analyze_wrangler <<-TOML
      name = "api"
      compatibility_date = "2024-01-01"

      [[routes]]
      pattern = "api.example.com/*"
      zone_name = "example.com"

      [[routes]]
      pattern = "example.com/api/*"
      zone_name = "example.com"
      TOML

    endpoints.map(&.url).sort!.should eq ["api.example.com/*", "example.com/api/*"]
    endpoints.each do |endpoint|
      endpoint.method.should eq "ANY"
      tag_descriptions(endpoint, "wrangler-zone").should eq ["example.com"]
    end
  end

  it "extracts JSON-formatted routes" do
    endpoints = analyze_wrangler(%({"name":"api","routes":[{"pattern":"app.example.com/*","zone_name":"example.com"}]}), ".jsonc")
    endpoints.size.should eq 1
    endpoints[0].url.should eq "app.example.com/*"
  end

  it "handles wrangler.jsonc with comments" do
    endpoints = analyze_wrangler(<<-JSONC, ".jsonc")
      // top-level config
      {
        "name": "api",
        /* multi
           line */
        "routes": [
          { "pattern": "api.example.com/*" }
        ]
      }
      JSONC
    endpoints.size.should eq 1
    endpoints[0].url.should eq "api.example.com/*"
  end
end
