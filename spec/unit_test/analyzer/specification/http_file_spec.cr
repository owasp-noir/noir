require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/http_file"

private def analyze_http_file(content : String, ext = ".http")
  path = File.tempname("http_file", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "http-file"
  locator.push "http-file", path

  options = create_test_options
  analyzer = Analyzer::Specification::HttpFile.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "http-file"
  File.delete(path) if path && File.exists?(path)
end

describe "HTTP/REST File Analyzer" do
  it "extracts method, path, query, path var and header" do
    endpoints = analyze_http_file <<-HTTP
      ### Get a user
      GET https://api.example.com/users/{{userId}}?verbose=true
      Authorization: Bearer secret
      HTTP

    endpoint = endpoints.find! { |e| e.method == "GET" }
    endpoint.url.should eq("/users/:userId")
    params = endpoint.params
    params.any? { |p| p.name == "verbose" && p.param_type == "query" }.should be_true
    params.any? { |p| p.name == "userId" && p.param_type == "path" }.should be_true
    params.any? { |p| p.name == "Authorization" && p.param_type == "header" }.should be_true
    # Content-Type-style headers are not surfaced; none present here anyway.
    params.any? { |p| p.param_type == "header" && p.name.downcase == "content-type" }.should be_false
  end

  it "extracts JSON body params and drops a trailing HTTP version" do
    endpoints = analyze_http_file <<-HTTP
      POST https://api.example.com/users HTTP/1.1
      Content-Type: application/json

      {
        "name": "noir",
        "email": "noir@example.com"
      }
      HTTP

    endpoint = endpoints.find! { |e| e.method == "POST" }
    endpoint.url.should eq("/users")
    endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
    endpoint.params.any? { |p| p.name == "email" && p.param_type == "json" }.should be_true
  end

  it "does not leak response-handler scripts into endpoints" do
    endpoints = analyze_http_file <<-HTTP
      ### Create order
      POST https://api.example.com/orders
      Content-Type: application/json

      { "item": "widget" }

      > {%
          client.test("ok", function() {
              client.assert(response.status === 200);
          });
      %}

      ### List orders
      GET https://api.example.com/orders
      HTTP

    endpoints.size.should eq(2)
    urls = endpoints.map(&.url)
    urls.should contain("/orders")
    # The `client`, `response` and `assert` tokens must not become endpoints.
    endpoints.none? { |e| e.url.includes?("client") || e.url.includes?("assert") }.should be_true
  end

  it "resolves in-file @variables in the request URL" do
    endpoints = analyze_http_file <<-HTTP
      @baseUrl = https://api.example.com

      GET {{baseUrl}}/health
      HTTP

    endpoints.size.should eq(1)
    endpoints.first.url.should eq("/health")
  end

  it "does not treat verb-initial prose as a request" do
    endpoints = analyze_http_file <<-HTTP
      Get started with the API.
      Delete the old files first.
      HTTP

    endpoints.size.should eq(0)
  end

  it "parses .rest files the same as .http" do
    endpoints = analyze_http_file("GET https://api.example.com/ping\n", ".rest")
    endpoints.size.should eq(1)
    endpoints.first.url.should eq("/ping")
    endpoints.first.method.should eq("GET")
  end
end
