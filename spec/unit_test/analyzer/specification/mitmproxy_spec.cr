require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/mitmproxy"
require "../../../../src/utils/tnetstring"

private def header(name : String, value : String) : Tnetstring::Value
  [name.as(Tnetstring::Value), value.as(Tnetstring::Value)].as(Tnetstring::Value)
end

private def version_value(major : Int64, minor : Int64 = 0_i64, patch : Int64 = 0_i64) : Tnetstring::Value
  arr = [major.as(Tnetstring::Value), minor.as(Tnetstring::Value), patch.as(Tnetstring::Value)] of Tnetstring::Value
  arr.as(Tnetstring::Value)
end

private def flow(request : Hash(String, Tnetstring::Value),
                 type : String = "http",
                 version : Tnetstring::Value? = nil) : Hash(String, Tnetstring::Value)
  dict = {
    "type"    => type.as(Tnetstring::Value),
    "request" => request.as(Tnetstring::Value),
  } of String => Tnetstring::Value
  v = version || version_value(3_i64)
  dict["version"] = v
  dict
end

private def write_flows(path : String, flows : Array(Hash(String, Tnetstring::Value)))
  File.open(path, "wb") do |io|
    flows.each do |f|
      io.write(Tnetstring.encode(f.as(Tnetstring::Value)))
    end
  end
end

private def analyze_flows(flows : Array(Hash(String, Tnetstring::Value)), url : String = "https://example.com") : Array(Endpoint)
  path = File.tempname("mitmproxy", ".mitm")
  write_flows(path, flows)
  locator = CodeLocator.instance
  locator.clear "mitmproxy-path"
  locator.push "mitmproxy-path", path

  options = create_test_options
  options["url"] = YAML::Any.new(url)
  analyzer = Analyzer::Specification::Mitmproxy.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

describe "Mitmproxy Analyzer" do
  it "emits an endpoint per HTTP flow with method/path/headers" do
    request = {
      "method"  => "GET".as(Tnetstring::Value),
      "scheme"  => "https".as(Tnetstring::Value),
      "host"    => "example.com".as(Tnetstring::Value),
      "port"    => 443_i64.as(Tnetstring::Value),
      "path"    => "/api/users?active=1".as(Tnetstring::Value),
      "headers" => [
        header("Host", "example.com"),
        header("Cookie", "session=abc; remember=1"),
      ].as(Tnetstring::Value),
      "content" => "".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request)])
    endpoints.size.should eq 1
    ep = endpoints.first
    ep.url.should eq "/api/users?active=1"
    ep.method.should eq "GET"

    query = ep.params.select { |p| p.param_type == "query" }
    query.map(&.name).should eq ["active"]
    query.first.value.should eq "1"

    headers = ep.params.select { |p| p.param_type == "header" }.map(&.name)
    headers.should contain "Host"
    headers.should contain "Cookie"

    cookies = ep.params.select { |p| p.param_type == "cookie" }.map { |p| {p.name, p.value} }
    cookies.should contain({"session", "abc"})
    cookies.should contain({"remember", "1"})
  end

  it "extracts form bodies and respects JSON content-type" do
    form_request = {
      "method"  => "POST".as(Tnetstring::Value),
      "scheme"  => "https".as(Tnetstring::Value),
      "host"    => "example.com".as(Tnetstring::Value),
      "port"    => 443_i64.as(Tnetstring::Value),
      "path"    => "/login".as(Tnetstring::Value),
      "headers" => [
        header("Content-Type", "application/x-www-form-urlencoded"),
      ].as(Tnetstring::Value),
      "content" => "user=alice&pw=secret".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    json_request = {
      "method"  => "POST".as(Tnetstring::Value),
      "scheme"  => "https".as(Tnetstring::Value),
      "host"    => "example.com".as(Tnetstring::Value),
      "port"    => 443_i64.as(Tnetstring::Value),
      "path"    => "/graphql".as(Tnetstring::Value),
      "headers" => [
        header("Content-Type", "application/json"),
      ].as(Tnetstring::Value),
      "content" => %({"query":"{me{id}}"}).as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(form_request), flow(json_request)])
    endpoints.size.should eq 2

    login = endpoints.find!(&.url.includes?("/login"))
    form_params = login.params.select { |p| p.param_type == "form" }.map { |p| {p.name, p.value} }
    form_params.should contain({"user", "alice"})
    form_params.should contain({"pw", "secret"})

    graphql = endpoints.find!(&.url.includes?("/graphql"))
    body = graphql.params.find! { |p| p.param_type == "json" }
    body.name.should eq "body"
    body.value.should contain "me"
  end

  it "marks websocket upgrades with ws protocol" do
    request = {
      "method"  => "GET".as(Tnetstring::Value),
      "scheme"  => "https".as(Tnetstring::Value),
      "host"    => "example.com".as(Tnetstring::Value),
      "port"    => 443_i64.as(Tnetstring::Value),
      "path"    => "/ws".as(Tnetstring::Value),
      "headers" => [
        header("Upgrade", "websocket"),
      ].as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request)])
    endpoints.first.protocol.should eq "ws"
  end

  it "accepts modern flow format versions (single integer)" do
    request = {
      "method" => "GET".as(Tnetstring::Value),
      "scheme" => "https".as(Tnetstring::Value),
      "host"   => "example.com".as(Tnetstring::Value),
      "port"   => 443_i64.as(Tnetstring::Value),
      "path"   => "/api".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request, version: 20_i64.as(Tnetstring::Value))])
    endpoints.size.should eq 1
    endpoints.first.url.should eq "/api"
  end

  it "skips flows from unsupported (pre-3.x) versions" do
    request = {
      "method" => "GET".as(Tnetstring::Value),
      "scheme" => "https".as(Tnetstring::Value),
      "host"   => "example.com".as(Tnetstring::Value),
      "port"   => 443_i64.as(Tnetstring::Value),
      "path"   => "/api".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request, version: version_value(2_i64))])
    endpoints.should be_empty
  end

  it "filters out flows whose host does not match the --url option" do
    request = {
      "method" => "GET".as(Tnetstring::Value),
      "scheme" => "https".as(Tnetstring::Value),
      "host"   => "other.example.org".as(Tnetstring::Value),
      "port"   => 443_i64.as(Tnetstring::Value),
      "path"   => "/api".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request)], url: "https://example.com")
    endpoints.should be_empty
  end

  it "emits one endpoint per flow in a multi-flow capture" do
    requests = [
      "/a", "/b", "/c",
    ].map do |p|
      {
        "method" => "GET".as(Tnetstring::Value),
        "scheme" => "https".as(Tnetstring::Value),
        "host"   => "example.com".as(Tnetstring::Value),
        "port"   => 443_i64.as(Tnetstring::Value),
        "path"   => p.as(Tnetstring::Value),
      } of String => Tnetstring::Value
    end

    endpoints = analyze_flows(requests.map { |r| flow(r) })
    endpoints.map(&.url).sort!.should eq ["/a", "/b", "/c"]
  end

  it "salvages prior flows when the stream is truncated mid-record" do
    good = {
      "method" => "GET".as(Tnetstring::Value),
      "scheme" => "https".as(Tnetstring::Value),
      "host"   => "example.com".as(Tnetstring::Value),
      "port"   => 443_i64.as(Tnetstring::Value),
      "path"   => "/ok".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    path = File.tempname("mitmproxy-trunc", ".mitm")
    File.open(path, "wb") do |io|
      encoded = Tnetstring.encode(flow(good).as(Tnetstring::Value))
      io.write(encoded)
      io.write("9999:incomplete".to_slice)
    end

    begin
      locator = CodeLocator.instance
      locator.clear "mitmproxy-path"
      locator.push "mitmproxy-path", path

      options = create_test_options
      options["url"] = YAML::Any.new("https://example.com")
      analyzer = Analyzer::Specification::Mitmproxy.new options
      endpoints = analyzer.analyze
      endpoints.map(&.url).should eq ["/ok"]
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "ignores non-http flows" do
    request = {
      "method" => "GET".as(Tnetstring::Value),
      "host"   => "example.com".as(Tnetstring::Value),
      "path"   => "/x".as(Tnetstring::Value),
    } of String => Tnetstring::Value

    endpoints = analyze_flows([flow(request, type: "dns")])
    endpoints.should be_empty
  end
end
