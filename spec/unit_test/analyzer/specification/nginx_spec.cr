require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/nginx"

private def analyze_nginx(content : String)
  path = File.tempname("nginx", ".conf")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "nginx-spec"
  locator.push "nginx-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::Nginx.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Nginx Analyzer" do
  it "emits each location block with its modifier as path-type" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 443 ssl;
          server_name api.example.com;

          location /v1/users         { proxy_pass http://users; }
          location ~ ^/admin/.*      { auth_basic "x"; proxy_pass http://admin; }
          location = /healthz        { return 200 "ok"; }
          location ^~ /static/       { root /var/www; }
      }
      CONF

    pairs = endpoints.map { |e| {e.url, tag_descriptions(e, "nginx-path-type").first} }.sort!
    pairs.should eq([
      {"/healthz", "exact"},
      {"/static/", "prefix-stop"},
      {"/v1/users", "prefix"},
      {"^/admin/.*", "regex"},
    ])
    endpoints.each(&.method.should(eq("ANY")))
    endpoints.each(&.protocol.should(eq("https")))
  end

  it "emits method-specific endpoints from if (\\$request_method) blocks" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 80;
          server_name example.com;
          location /api/ {
              proxy_pass http://api/;
              if ($request_method = POST) {
                  return 405;
              }
          }
      }
      CONF
    pairs = endpoints.map { |e| {e.url, e.method} }.sort!
    pairs.should eq([
      {"/api/", "ANY"},
      {"/api/", "POST"},
    ])
  end

  it "preserves hash characters in regex locations" do
    endpoints = analyze_nginx <<-CONF
      server {
          location ~* (?:#.*#|\\.(?:bak|conf|log)|~)$ {
              deny all;
          }
      }
      CONF

    endpoints.map(&.url).should eq(["(?:#.*#|\\.(?:bak|conf|log)|~)$"])
  end

  it "skips internal named and templated locations" do
    endpoints = analyze_nginx <<-CONF
      server {
          location @fallback { proxy_pass http://fallback; }
          location {{ .Path }} { proxy_pass http://backend; }
          location /public { proxy_pass http://public; }
      }
      CONF

    endpoints.map(&.url).should eq(["/public"])
  end

  it "tracks multiple server blocks independently" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 80;
          server_name a.example.com;
          location /foo { }
      }
      server {
          listen 80;
          server_name b.example.com;
          location /bar { }
      }
      CONF

    pairs = endpoints.map { |e| {e.url, tag_descriptions(e, "nginx-host").first} }.sort!
    pairs.should eq([
      {"/bar", "b.example.com"},
      {"/foo", "a.example.com"},
    ])
  end
end
