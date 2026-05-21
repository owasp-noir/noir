require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/serverless_framework"

private def analyze_serverless(content : String, ext = ".yml")
  path = File.tempname("serverless", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "serverless-framework-spec"
  locator.push "serverless-framework-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::ServerlessFramework.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Serverless Framework Analyzer" do
  it "extracts http events with method/path under provider stage" do
    endpoints = analyze_serverless <<-YAML
      service: my-api
      provider:
        name: aws
        stage: dev
      functions:
        listUsers:
          handler: src/users.list
          events:
            - http:
                method: get
                path: /users
                cors: true
        createUser:
          handler: src/users.create
          events:
            - http:
                method: post
                path: /users
                authorizer: aws_iam
      YAML

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/dev/users", "GET"},
      {"/dev/users", "POST"},
    ])
  end

  it "supports httpApi events with v2 HTTP API" do
    endpoints = analyze_serverless <<-YAML
      service: my-api
      provider:
        name: aws
      functions:
        getUser:
          handler: x
          events:
            - httpApi:
                method: GET
                path: /users/{id}
      YAML

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/users/{id}"
    endpoints[0].method.should eq "GET"
    tag_descriptions(endpoints[0], "serverless-event").should eq ["httpapi"]
  end

  it "parses shorthand `METHOD /path` form" do
    endpoints = analyze_serverless <<-YAML
      service: my-api
      provider:
        name: aws
      functions:
        ping:
          handler: x
          events:
            - http: GET /health
      YAML

    endpoints.size.should eq 1
    endpoints[0].url.should eq "/health"
    endpoints[0].method.should eq "GET"
  end

  it "tags cors, private, and authorizer flags" do
    endpoints = analyze_serverless <<-YAML
      service: my-api
      provider:
        name: aws
      functions:
        a:
          handler: x
          events:
            - http:
                method: get
                path: /a
                cors: true
                private: true
                authorizer:
                  name: customAuth
      YAML

    endpoint = endpoints[0]
    tag_descriptions(endpoint, "serverless-cors").should eq ["true"]
    tag_descriptions(endpoint, "serverless-private").should eq ["true"]
    tag_descriptions(endpoint, "serverless-auth").should eq ["customAuth"]
  end

  it "parses serverless.json variants" do
    json = <<-JSON
      {
        "service": "my-api",
        "provider": {"name": "aws", "stage": "prod"},
        "functions": {
          "a": {"events": [{"http": {"method": "post", "path": "/a"}}]}
        }
      }
      JSON
    endpoints = analyze_serverless(json, ".json")
    endpoints.size.should eq 1
    endpoints[0].url.should eq "/prod/a"
    endpoints[0].method.should eq "POST"
  end
end
