require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/apache_httpd"

private def analyze_apache(content : String, ext = ".conf")
  path = File.tempname("apache", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "apache-httpd-spec"
  locator.push "apache-httpd-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::ApacheHttpd.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Apache httpd Analyzer" do
  it "extracts Location, LocationMatch, Alias, RewriteRule entries" do
    endpoints = analyze_apache <<-CONF
      <VirtualHost *:443>
          ServerName api.example.com

          <Location /v1/users>
              ProxyPass http://users:8080/users
          </Location>
          <LocationMatch "^/admin/(.*)$">
              AuthType Basic
          </LocationMatch>
          Alias /static /var/www/static
          RewriteRule ^/api/(.*)$ /v1/$1 [L,QSA]
      </VirtualHost>
      CONF

    pairs = endpoints.map { |e| {e.url, tag_descriptions(e, "apache-path-type").first} }.sort!
    pairs.should eq([
      {"/static", "alias"},
      {"/v1/users", "prefix"},
      {"^/admin/(.*)$", "regex"},
      {"^/api/(.*)$", "rewrite-source"},
    ])
    endpoints.each do |e|
      tag_descriptions(e, "apache-host").should eq ["api.example.com"]
      e.method.should eq "ANY"
    end
  end

  it "carries rewrite target as a tag" do
    endpoints = analyze_apache "RewriteRule ^/old/(.*)$ /new/$1 [L,QSA]\n"
    endpoints.size.should eq 1
    tag_descriptions(endpoints[0], "apache-rewrite-target").should eq ["/new/$1"]
  end

  it "extracts proxy, script alias, and redirect directives" do
    endpoints = analyze_apache <<-CONF
      <VirtualHost *:443>
          ServerName proxy.example.com
          ProxyPass /api http://backend:8080/
          ProxyPassMatch ^/ws/(.*)$ ws://backend/$1
          ScriptAlias /cgi-bin/ "/var/www/cgi-bin/"
          Redirect permanent /old https://example.com/new
          RedirectMatch 301 ^/legacy/(.*)$ /new/$1
      </VirtualHost>
      CONF

    pairs = endpoints.map { |e| {e.url, tag_descriptions(e, "apache-path-type").first} }.sort!
    pairs.should eq([
      {"/api", "proxy"},
      {"/cgi-bin/", "script-alias"},
      {"/old", "redirect"},
      {"^/legacy/(.*)$", "redirect-regex"},
      {"^/ws/(.*)$", "proxy-regex"},
    ])
    endpoints.each do |e|
      tag_descriptions(e, "apache-host").should eq ["proxy.example.com"]
    end
  end

  it "skips location-scoped proxy targets and non-url alias arguments" do
    endpoints = analyze_apache <<-CONF
      <Location /backend>
          ProxyPass http://backend:8080/
      </Location>
      <LocationMatch "^/files/(.*)$">
          Alias /var/www/files/$1
      </LocationMatch>
      CONF

    endpoints.map(&.url).sort!.should eq ["/backend", "^/files/(.*)$"]
  end

  it "skips no-substitution and static asset rewrites" do
    endpoints = analyze_apache <<-CONF, ".htaccess"
      RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
      RewriteRule ^(?:build|tests)/.* - [R=404,L]
      RewriteRule ^(.*css_[a-zA-Z0-9-_]+)\\.css$ $1\\.css\\.br [QSA]
      RewriteRule ^remote/(.*) remote.php [L]
      CONF

    endpoints.map(&.url).should eq ["^remote/(.*)"]
  end

  it "supports multiple ServerAlias hosts" do
    endpoints = analyze_apache <<-CONF
      <VirtualHost *:80>
          ServerName main.example.com
          ServerAlias alt1.example.com alt2.example.com
          <Location /metrics>
          </Location>
      </VirtualHost>
      CONF

    hosts = endpoints.flat_map { |e| tag_descriptions(e, "apache-host") }.sort!
    hosts.should eq ["alt1.example.com", "alt2.example.com", "main.example.com"]
  end
end
