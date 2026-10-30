require "file_utils"
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

# `files`: relative path => content, written under one temp directory and all
# registered, as the detector registers every nginx file it sees. Returns the
# endpoints and that directory.
private def analyze_nginx_files(files : Hash(String, String))
  dir = File.tempname("nginx_tree")
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::NGINX_SPEC
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    locator.push Noir::LocatorKeys::NGINX_SPEC, path
  end
  {Analyzer::Specification::Nginx.new(create_test_options).analyze, dir + "/"}
ensure
  FileUtils.rm_rf(dir) if dir
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

  # nginx reads `location =/x` like `location = /x`.
  it "reads a modifier glued to the URI" do
    endpoints = analyze_nginx <<-'CONF'
      server {
          location =/items { return 301 /catalog/items; }
          location ~^/users/(\d+)$ { proxy_pass http://backend; }
          location ~*^/Files/ { proxy_pass http://backend; }
          location ^~/static/ { root /var/www; }
      }
      CONF

    endpoints.map { |e| {e.url, e.kind, tag_descriptions(e, "nginx-path-type").first} }.sort!.should eq([
      {"/Files/", "", "regex-i"},
      {"/items", "", "exact"},
      {"/static/", "", "prefix-stop"},
      {"/users/(\\d+)", "regex", "regex"},
    ])
  end

  # A client request for an `internal` location gets a 404; only nginx's own
  # redirects reach it.
  it "drops internal locations and their method rows but not a nested location" do
    endpoints = analyze_nginx <<-CONF
      server {
          location = /_auth {
              internal;
              proxy_pass http://auth/check;
          }
          location /protected/ {
              internal;
              if ($request_method = POST) { return 200; }
              location /protected/open/ { proxy_pass http://open; }
              alias /var/files/;
          }
          location /items {
              # internal;
              proxy_pass http://backend;
          }
      }
      CONF

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/items", "ANY"},
      {"/protected/open/", "ANY"},
    ])
  end

  it "keeps a location whose internal a template decides" do
    endpoints = analyze_nginx <<-CONF
      server {
          location /d {
              {{ if .Values.private }}internal;{{ end }}
              proxy_pass http://x;
          }
          location /e {
              {{ if .Values.private }}
              internal;
              {{ end }}
              proxy_pass http://x;
          }
      }
      CONF

    endpoints.map(&.url).sort!.should eq(["/d", "/e"])
  end

  it "does not read the catch-all server_name as a host" do
    endpoints = analyze_nginx <<-CONF
      server {
          listen 80 default_server;
          server_name _ "" api.example.com;
          location /health { return 200 ok; }
      }
      server {
          server_name _;
          location /other { return 200 ok; }
      }
      CONF

    endpoints.map { |e| {e.url, tag_descriptions(e, "nginx-host")} }.sort!.should eq([
      {"/health", ["api.example.com"]},
      {"/other", [] of String},
    ])
  end

  # `(^/a$)` is the path `/a`; an alternation stays a pattern.
  it "reads a regex wrapped in one group like the bare regex" do
    endpoints = analyze_nginx <<-CONF
      server {
          location ~ (^/items/(.+)/files$) { proxy_pass http://backend; }
          location ~ (^/users/(.+)/avatar$)|(^/users/(.+)/banner$) { proxy_pass http://backend; }
      }
      CONF

    endpoints.map(&.url).sort!.should eq([
      "(^/users/(.+)/avatar$)|(^/users/(.+)/banner$)",
      "/items/(.+)/files",
    ])
  end

  # Locations split into `include`d files are the usual layout (`conf.d`,
  # `snippets`, `sites-enabled`). They were read on their own, without the
  # server's host, TLS or access rules.
  describe "include" do
    it "reads an included file inside the server block that includes it" do
      endpoints, dir = analyze_nginx_files({
        "nginx.conf" => <<-CONF,
          http {
              server {
                  listen 443 ssl;
                  server_name api.example.com;
                  auth_basic "staff";
                  include locations/*.conf;
              }
              server {
                  listen 80;
                  server_name www.example.com;
                  include /etc/nginx/locations/users.conf;
              }
          }
          CONF
        "locations/users.conf" => <<-CONF,
          location /users/ {
              proxy_pass http://backend;
          }
          CONF
        "locations/items.conf" => <<-CONF,
          location /items { allow all; satisfy any; proxy_pass http://backend; }
          CONF
        "unrelated/users.conf" => <<-CONF,
          location /elsewhere { proxy_pass http://backend; }
          CONF
      })

      rows = endpoints.map do |e|
        {e.url, e.protocol, tag_descriptions(e, "nginx-host"),
         e.details.code_paths.map { |info| {info.path.lchop(dir), info.line} },
         e.tags.select(&.name.==("auth")).map { |t| {t.description, t.path.try(&.lchop(dir)), t.line} }}
      end
      none = [] of Tuple(String, String?, Int32?)
      rows.sort_by! { |row| {row[0], row[1]} }.should eq([
        {"/elsewhere", "http", [] of String, [{"unrelated/users.conf", 1}], none},
        {"/items", "https", ["api.example.com"], [{"locations/items.conf", 1}], none},
        {"/users/", "http", ["www.example.com"], [{"locations/users.conf", 1}], none},
        {"/users/", "https", ["api.example.com"], [{"locations/users.conf", 1}],
         [{"Protected by nginx auth_basic \"staff\"", "nginx.conf", 5}]},
      ])
    end

    # The includer's directory is literal text, not a glob; a pattern nginx
    # would reject resolves to nothing and costs only itself.
    it "reads glob characters in the directory literally and survives a bad pattern" do
      {"app[1", "{{cookiecutter.slug}}", "a{b,c}"}.each do |dir|
        endpoints, _ = analyze_nginx_files({
          "#{dir}/nginx.conf"    => "server {\n    listen 443 ssl;\n    include conf.d/*.conf;\n    include conf.d/[x.conf;\n}\n",
          "#{dir}/conf.d/x.conf" => "location /x { proxy_pass http://x; }\n",
        })
        endpoints.map { |e| {e.url, e.protocol} }.should eq([{"/x", "https"}]), dir
      end
    end

    it "reads files that only include each other on their own" do
      endpoints, _ = analyze_nginx_files({
        "a.conf" => "server {\n    server_name a.com;\n    include b.conf;\n    location /a { proxy_pass http://x; }\n}\n",
        "b.conf" => "location /b { proxy_pass http://x; }\ninclude a.conf;\n",
      })
      endpoints.map(&.url).uniq!.sort!.should eq(["/a", "/b"])
    end

    # nginx looks no further than its prefix, so one app's include does not
    # bind another directory's `conf.d` (and its auth and TLS with it).
    it "does not search above the configuration prefix" do
      endpoints, _ = analyze_nginx_files({
        "app1/nginx.conf"    => "server {\n    listen 443 ssl;\n    auth_basic \"app1\";\n    include /etc/nginx/conf.d/*.conf;\n    location /app1 { proxy_pass http://x; }\n}\n",
        "conf.d/public.conf" => "location /public { proxy_pass http://x; }\n",
      })
      endpoints.map { |e| {e.url, e.protocol, e.tags.count(&.name.==("auth"))} }.sort!.should eq([
        {"/app1", "https", 1},
        {"/public", "http", 0},
      ])
    end

    it "resolves a relative include from the configuration prefix, not the file itself" do
      endpoints, _ = analyze_nginx_files({
        "nginx/sites-enabled/app.conf" => <<-CONF,
          server {
              server_name app.example.com;
              include snippets/api.conf;
          }
          CONF
        "nginx/snippets/api.conf" => <<-CONF,
          location /api { proxy_pass http://backend; }
          include snippets/api.conf;
          CONF
      })

      endpoints.map { |e| {e.url, tag_descriptions(e, "nginx-host")} }.should eq([{"/api", ["app.example.com"]}])
    end
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

    # `satisfy any; allow all;` is how a sub-location of an auth_basic server
    # is opened: either check is enough, and the address check admits all.
    it "reads satisfy any as alternatives" do
      endpoints = analyze_nginx <<-CONF
        http {
          server {
            auth_basic "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
            location /admin { proxy_pass http://app; }
            location /public {
              satisfy any;
              allow all;
              proxy_pass http://app;
            }
          }
          server {
            location /sat {
              satisfy any;
              allow all;
              auth_basic "x";
              proxy_pass http://sat;
            }
            location /satok {
              satisfy any;
              allow 10.0.0.0/8;
              deny all;
              auth_basic "x";
              proxy_pass http://satok;
            }
            location /all-allow {
              satisfy all;
              allow all;
              auth_basic "x";
              proxy_pass http://all;
            }
          }
        }
        CONF

      guards.call(endpoints).should eq([
        {"/admin", ["Protected by nginx auth_basic \"Restricted\""]},
        {"/all-allow", ["Protected by nginx auth_basic \"x\""]},
        {"/public", [] of String},
        {"/sat", [] of String},
        {"/satok", ["Protected by nginx auth_basic \"x\" or allow 10.0.0.0/8; deny all"]},
      ])
    end

    # A template `if`, a template action in the value or an nginx variable
    # decides the value at deploy time; `auth_basic $var` can be mapped to
    # `off`. `${VAR}` braces are not blocks.
    it "marks settings a template or variable decides" do
      endpoints = analyze_nginx <<-CONF
        server
        {
          listen 80;
          location /tmpl {
            {{ if .AuthEnabled }}
            auth_basic "{{ .Realm }}";
            {{ end }}
            proxy_pass http://app;
          }
          location /envsubst {
            auth_basic ${AUTH_REALM};
            proxy_pass http://app;
          }
          location /var {
            auth_basic $authvar;
            proxy_pass http://app;
          }
          location /var-and-request {
            auth_basic $authvar;
            auth_request /auth;
            proxy_pass http://app;
          }
          location /after {
            auth_basic "plain";
            proxy_pass http://app;
          }
        }
        server {
          auth_basic "site";
          location /maybe-open {
            {{ if .Public }}auth_basic off;{{ end }}
            proxy_pass http://app;
          }
        }
        CONF

      guards.call(endpoints).should eq([
        {"/after", ["Protected by nginx auth_basic \"plain\""]},
        {"/envsubst", ["Protected by nginx auth_basic ${AUTH_REALM} (a setting can make it public)"]},
        {"/maybe-open", ["Protected by nginx auth_basic \"site\" (a setting can make it public)"]},
        {"/tmpl", ["Protected by nginx auth_basic (a setting can make it public)"]},
        {"/var", ["Protected by nginx auth_basic $authvar (a setting can make it public)"]},
        {"/var-and-request", ["Protected by nginx auth_basic $authvar, auth_request /auth"]},
      ])
    end

    it "reads a server block whose brace is on the next line and http-level access lists" do
      endpoints = analyze_nginx <<-CONF
        http
        {
          allow 10.0.0.0/8;
          deny all;
          server
          {
            location /x { proxy_pass http://x; }
            location /y { allow all; proxy_pass http://y; }
            location /z { deny 1.2.3.4; proxy_pass http://z; }
          }
          server {
            auth_basic "x";
            location /a { proxy_pass http://a; }
          }
        }
        CONF

      guards.call(endpoints).should eq([
        {"/a", ["Protected by nginx auth_basic \"x\", allow 10.0.0.0/8; deny all"]},
        {"/x", ["Protected by nginx allow 10.0.0.0/8; deny all"]},
        {"/y", [] of String},
        {"/z", [] of String},
      ])
    end
  end
end
