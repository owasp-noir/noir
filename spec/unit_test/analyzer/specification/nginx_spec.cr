require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/nginx"

private def analyze_nginx(content : String)
  path = File.tempname("nginx", ".conf")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::NGINX_SPEC
  locator.push Noir::LocatorKeys::NGINX_SPEC, path

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
      {"/admin/.*", "regex"},
      {"/healthz", "exact"},
      {"/static/", "prefix-stop"},
      {"/v1/users", "prefix"},
    ])
    endpoints.each(&.method.should(eq("ANY")))
    endpoints.each(&.protocol.should(eq("https")))
  end

  it "drops denial-only locations but keeps responses and content handlers" do
    endpoints = analyze_nginx <<-CONF
      server {
          location /health { return 200 'ok'; }
          location / { return 404; }
          location /private {
              deny all;
          }
          location /mixed {
              proxy_pass http://app;
              return 404;
          }
          location /legacy {
              return 410;
              location /legacy/feed { proxy_pass http://app; }
          }
      }
      CONF

    endpoints.map(&.url).sort!.should eq(["/health", "/legacy/feed", "/mixed"])
  end

  it "marks a regex location as kind regex only while it still reads as a pattern" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 80;
          location ~ ^/(fonts|assets)/.*\\.(eot|ttf)$ { expires 1y; }
          location ~ ^/api/v1/users$                 { proxy_pass http://api; }
          location ~ \\.php$                          { fastcgi_pass php; }
          location /plain/                           { proxy_pass http://app; }
      }
      CONF

    endpoints.map { |e| {e.url, e.kind} }.sort!.should eq([
      {".php", "regex"},
      {"/(fonts|assets)/.*.(eot|ttf)", "regex"},
      {"/api/v1/users", ""},
      {"/plain/", ""},
    ])
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
              proxy_pass http://assets;
          }
      }
      CONF

    endpoints.map(&.url).should eq(["(?:#.*#|.(?:bak|conf|log)|~)"])
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

  # The method endpoint was emitted with no modifier, so a regex location's
  # anchors survived on it (`^/v1$` next to `/v1`) and it was tagged prefix.
  it "gives a method block its regex location's path and path-type" do
    endpoints = analyze_nginx <<-CONF
      server {
          location ~ ^/v1/items$ {
              if ($request_method = PUT) { return 405; }
          }
      }
      CONF

    endpoints.map { |e| {e.url, e.method, tag_descriptions(e, "nginx-path-type").first} }.sort!.should eq([
      {"/v1/items", "ANY", "regex"},
      {"/v1/items", "PUT", "regex"},
    ])
  end

  # The regex's `{1,2}` was counted as structure, so its `}` popped the
  # location before its `{` on the next line was ever read.
  it "keeps a regex location whose block opens on the next line" do
    endpoints = analyze_nginx <<-'CONF'
      server {
          location ~ ^/v\d{1,2}/u$
          {
              if ($request_method = POST) { return 200; }
          }
          location /after { }
      }
      CONF

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/after", "ANY"},
      {"/v\\d{1,2}/u", "ANY"},
      {"/v\\d{1,2}/u", "POST"},
    ])
  end

  # Each `}` of a one-line block or of an unpushed `@named` location used to
  # pop a frame it never pushed, closing /admin and then the server early.
  it "keeps frames balanced across one-line blocks and named locations" do
    endpoints = analyze_nginx <<-'CONF'
      server {
          listen 443 ssl;
          server_name a.example.com;
          location /admin {
              if ($bad_ua) { return 403; }
              return 200 '{"ok":true}';
              if ($request_method = POST) {
                  return 405;
              }
          }
          location @fallback {
              proxy_pass http://fallback;
          }
          location ~ ^/v\d{1,2}/items$ {
              proxy_pass http://items;
          }
          location /api
          {
              proxy_pass http://api;
          }
      }
      CONF

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/admin", "ANY"},
      {"/admin", "POST"},
      {"/api", "ANY"},
      {"/v\\d{1,2}/items", "ANY"},
    ])
    endpoints.each do |endpoint|
      endpoint.protocol.should eq("https")
      tag_descriptions(endpoint, "nginx-host").should eq(["a.example.com"])
    end
  end

  it "strips surrounding quotes from regex and prefix locations" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 80;
          location ~ "^/v[0-9]{1,2}/.+\\.json$" { proxy_pass http://api; }
          location ~ '^/v[0-9]{1,2}/items$'     { proxy_pass http://items; }
          location ~ "^/api/v1/users$"          { proxy_pass http://users; }
          location "/quoted/prefix"             { proxy_pass http://prefix; }
          location = '/quoted/exact'            { return 200 "ok"; }
      }
      CONF

    endpoints.map { |e| {e.url, e.kind, tag_descriptions(e, "nginx-path-type").first} }.sort!.should eq([
      {"/api/v1/users", "", "regex"},
      {"/quoted/exact", "", "exact"},
      {"/quoted/prefix", "", "prefix"},
      {"/v[0-9]{1,2}/.+.json", "regex", "regex"},
      {"/v[0-9]{1,2}/items", "regex", "regex"},
    ])
  end

  it "preserves unquoted path with method block inside quoted regex location" do
    endpoints = analyze_nginx <<-CONF
      server {
          location ~ "^/v[0-9]{1,2}/.+\\.json$" {
              if ($request_method = POST) { return 200; }
          }
      }
      CONF

    endpoints.map { |e| {e.url, e.method, e.kind} }.sort!.should eq([
      {"/v[0-9]{1,2}/.+.json", "ANY", "regex"},
      {"/v[0-9]{1,2}/.+.json", "POST", "regex"},
    ])
  end

  describe "access rules" do
    guards = ->(endpoints : Array(Endpoint)) do
      endpoints.map { |e| {e.url, e.tags.select { |t| t.name == "auth" }.map(&.description)} }.sort!
    end

    it "turns auth_basic, auth_request and allow/deny all into guards" do
      endpoints = analyze_nginx <<-CONF
        server {
            location /admin/ {
                allow 127.0.0.1;
                deny all;
                proxy_pass http://backend;
            }
            location /reports/ {
                auth_basic "restricted";
                auth_basic_user_file /etc/nginx/htpasswd;
                proxy_pass http://backend;
            }
            location /items {
                auth_request /_auth;
                proxy_pass http://backend;
            }
            location /public {
                proxy_pass http://backend;
            }
        }
        CONF

      guards.call(endpoints).should eq([
        {"/admin/", ["Protected by nginx allow 127.0.0.1; deny all"]},
        {"/items", ["Protected by nginx auth_request /_auth"]},
        {"/public", [] of String},
        {"/reports/", ["Protected by nginx auth_basic \"restricted\""]},
      ])
      reports = endpoints.find! { |e| e.url == "/reports/" }
      reports.tags.find!(&.name.==("auth")).line.should eq(8)
    end

    it "inherits from server and http blocks unless a location overrides it" do
      endpoints = analyze_nginx <<-CONF
        http {
            auth_basic "site";
            server {
                location /inherited { proxy_pass http://a; }
                location /health {
                    auth_basic off;
                    proxy_pass http://a;
                }
                location /outer {
                    location /outer/inner { proxy_pass http://a; }
                    proxy_pass http://a;
                }
            }
            server {
                auth_basic off;
                location /late { proxy_pass http://b; }
                allow 10.0.0.0/8;
                deny all;
            }
        }
        CONF

      guards.call(endpoints).should eq([
        {"/health", [] of String},
        {"/inherited", ["Protected by nginx auth_basic \"site\""]},
        {"/late", ["Protected by nginx allow 10.0.0.0/8; deny all"]},
        {"/outer", ["Protected by nginx auth_basic \"site\""]},
        {"/outer/inner", ["Protected by nginx auth_basic \"site\""]},
      ])
    end

    it "does not guard on open or unreachable access lists or on an if block" do
      endpoints = analyze_nginx <<-CONF
        server {
            location /allow-all {
                allow all;
                deny all;
                proxy_pass http://a;
            }
            location /blocklist {
                deny 192.0.2.1;
                proxy_pass http://a;
            }
            location /deny-only {
                deny all;
                proxy_pass http://a;
            }
            location /conditional {
                if ($bad) {
                    allow 127.0.0.1;
                    deny all;
                }
                proxy_pass http://a;
            }
            location /limit {
                limit_except GET { auth_basic "writes"; }
                proxy_pass http://a;
            }
        }
        CONF

      endpoints.size.should eq(5)
      guards.call(endpoints).each { |_, descriptions| descriptions.should be_empty }
    end
  end
end
