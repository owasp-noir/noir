require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/caddy"

private def analyze_caddy(content : String, ext = "")
  ext = ".caddy" if ext.empty?
  name = ext == ".json" ? File.tempname("caddy", ".json") : File.tempname("Caddyfile", "")
  path = name
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "caddy-spec"
  locator.push "caddy-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::Caddy.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Caddy Analyzer" do
  it "extracts handle / handle_path / redir entries with site host" do
    endpoints = analyze_caddy <<-CADDY
      api.example.com {
          handle /v1/* {
              reverse_proxy users:8080
          }
          handle_path /admin/* {
              basic_auth { admin $2y$... }
              reverse_proxy admin:3000
          }
          redir /old /new permanent
      }
      CADDY

    pairs = endpoints.map { |e| {e.url, tag_descriptions(e, "caddy-source").first} }.sort!
    pairs.should eq([
      {"/admin/*", "handle_path"},
      {"/old", "redir"},
      {"/v1/*", "handle"},
    ])
    endpoints.each { |e| tag_descriptions(e, "caddy-host").should eq ["api.example.com"] }
  end

  it "applies named matchers to subsequent handle directives" do
    endpoints = analyze_caddy <<-CADDY
      api.example.com {
          @api {
              method GET POST
              path /api/*
          }
          handle @api {
              reverse_proxy api:8000
          }
      }
      CADDY

    pairs = endpoints.map { |e| {e.url, e.method} }.sort!
    pairs.should eq([
      {"/api/*", "GET"},
      {"/api/*", "POST"},
    ])
  end

  it "parses caddy.json apps.http.servers.routes" do
    endpoints = analyze_caddy(<<-JSON, ".json")
      {
        "apps": {
          "http": {
            "servers": {
              "srv0": {
                "routes": [
                  {
                    "match": [
                      {
                        "host": ["api.example.com"],
                        "path": ["/v1/*"],
                        "method": ["GET"]
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      }
      JSON

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/v1/*"
    endpoints[0].method.should eq "GET"
    tag_descriptions(endpoints[0], "caddy-host").should eq ["api.example.com"]
  end
end
