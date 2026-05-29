require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/postman"

private def analyze_postman(content : String)
  path = File.tempname("postman", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "postman-json"
  locator.push "postman-json", path

  options = create_test_options
  analyzer = Analyzer::Specification::Postman.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "postman-json"
  File.delete(path) if path && File.exists?(path)
end

private def param_tuples(endpoint : Endpoint)
  endpoint.params.map { |p| {p.name, p.value, p.param_type} }
end

describe "Postman Analyzer" do
  it "resolves collection variables and extracts string requests" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Variable Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "variable": [
          { "key": "baseUrl", "value": "https://api.example.com/v1" }
        ],
        "item": [
          {
            "name": "Ping",
            "request": "{{baseUrl}}/ping?trace=true"
          }
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoint = endpoints.first
    endpoint.url.should eq "/v1/ping"
    endpoint.method.should eq "GET"
    param_tuples(endpoint).should contain({"trace", "true", "query"})
  end

  it "honors disabled Postman params and derives path variables from raw URLs" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Disabled Param Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "variable": [
          { "key": "baseUrl", "value": "https://api.example.com/v1" }
        ],
        "item": [
          {
            "name": "Get User",
            "request": {
              "method": "GET",
              "header": [
                { "key": "X-Trace", "value": "1" },
                { "key": "X-Off", "value": "0", "disabled": true },
                { "key": "Content-Type", "value": "application/json" },
                { "key": "Cookie", "value": "sid=abc; theme=dark" }
              ],
              "url": {
                "raw": "{{baseUrl}}/users/{{userId}}?page=1&debug=true",
                "query": [
                  { "key": "page", "value": "1" },
                  { "key": "debug", "value": "true", "disabled": true }
                ]
              }
            }
          }
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoint = endpoints.first
    endpoint.url.should eq "/v1/users/:userId"

    params = param_tuples(endpoint)
    params.should contain({"page", "1", "query"})
    params.should contain({"userId", "", "path"})
    params.should contain({"X-Trace", "1", "header"})
    params.should contain({"sid", "abc", "cookie"})
    params.should contain({"theme", "dark", "cookie"})
    params.should_not contain({"debug", "true", "query"})
    params.should_not contain({"X-Off", "0", "header"})
    endpoint.params.any? { |p| p.name == "Content-Type" }.should be_false
  end

  it "preserves single-brace path variable names" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Single Brace Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
          {
            "name": "Get User",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/users/{id}"
            }
          }
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoint = endpoints.first
    endpoint.url.should eq "/users/:id"
    param_tuples(endpoint).should contain({"id", "", "path"})
  end

  it "skips disabled form fields and extracts GraphQL body variables" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Body Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
          {
            "name": "Upload",
            "request": {
              "method": "POST",
              "body": {
                "mode": "formdata",
                "formdata": [
                  { "key": "file", "src": "avatar.png" },
                  { "key": "ignore", "value": "x", "disabled": true }
                ]
              },
              "url": "/upload"
            }
          },
          {
            "name": "GraphQL",
            "request": {
              "method": "POST",
              "body": {
                "mode": "graphql",
                "graphql": {
                  "query": "query User($id: ID!) { user(id: $id) { id } }",
                  "variables": "{\\"id\\":\\"123\\"}"
                }
              },
              "url": "/graphql"
            }
          }
        ]
      }
      JSON

    upload = endpoints.find!(&.url.==("/upload"))
    upload_params = param_tuples(upload)
    upload_params.should contain({"file", "avatar.png", "form"})
    upload_params.should_not contain({"ignore", "x", "form"})

    graphql = endpoints.find!(&.url.==("/graphql"))
    graphql_params = param_tuples(graphql)
    graphql_params.should contain({"query", "query User($id: ID!) { user(id: $id) { id } }", "json"})
    graphql_params.should contain({"id", "123", "json"})
  end
end
