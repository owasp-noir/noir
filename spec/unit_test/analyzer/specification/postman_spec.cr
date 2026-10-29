require "../../../spec_helper"
require "file_utils"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/postman"

private def analyze_postman(content : String)
  path = File.tempname("postman", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::POSTMAN_JSON
  locator.push Noir::LocatorKeys::POSTMAN_JSON, path

  options = create_test_options
  analyzer = Analyzer::Specification::Postman.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::POSTMAN_JSON
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

  it "extracts request-level auth as parameters" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Auth Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
          {
            "name": "Bearer",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/bearer",
              "auth": { "type": "bearer", "bearer": [ { "key": "token", "value": "abc" } ] }
            }
          },
          {
            "name": "ApiKeyQuery",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/apikey",
              "auth": { "type": "apikey", "apikey": [
                { "key": "key", "value": "X-Api-Key" },
                { "key": "value", "value": "secret" },
                { "key": "in", "value": "query" }
              ] }
            }
          },
          {
            "name": "Basic v2.0 object form",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/basic",
              "auth": { "type": "basic", "basic": { "username": "u", "password": "p" } }
            }
          }
        ]
      }
      JSON

    bearer = endpoints.find!(&.url.==("/bearer"))
    param_tuples(bearer).should contain({"Authorization", "Bearer abc", "header"})

    apikey = endpoints.find!(&.url.==("/apikey"))
    param_tuples(apikey).should contain({"X-Api-Key", "secret", "query"})

    basic = endpoints.find!(&.url.==("/basic"))
    param_tuples(basic).should contain({"Authorization", "", "header"})
  end

  it "inherits collection-level auth and lets requests override with noauth" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Inherited Auth Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "auth": { "type": "bearer", "bearer": [ { "key": "token", "value": "root" } ] },
        "item": [
          {
            "name": "Inherits",
            "request": { "method": "GET", "url": "https://api.example.com/inherits" }
          },
          {
            "name": "Opts out",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/public",
              "auth": { "type": "noauth" }
            }
          }
        ]
      }
      JSON

    inherits = endpoints.find!(&.url.==("/inherits"))
    param_tuples(inherits).should contain({"Authorization", "Bearer root", "header"})

    public_ep = endpoints.find!(&.url.==("/public"))
    public_ep.params.any? { |p| p.name == "Authorization" }.should be_false
  end

  it "normalizes Postman dynamic variables in the path to path params" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Dynamic Var Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
          {
            "name": "Anything",
            "request": {
              "method": "GET",
              "url": "https://api.example.com/anything/{{$guid}}"
            }
          }
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoint = endpoints.first
    endpoint.url.should eq "/anything/:guid"
    param_tuples(endpoint).should contain({"guid", "", "path"})
  end

  it "does not share details between requests in one collection" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {
          "name": "Details Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
          {
            "name": "Users",
            "request": {
              "method": "GET",
              "url": "/users"
            }
          },
          {
            "name": "GraphQL",
            "request": {
              "method": "POST",
              "url": "/graphql"
            }
          }
        ]
      }
      JSON

    users = endpoints.find!(&.url.==("/users"))
    graphql = endpoints.find!(&.url.==("/graphql"))

    users.details.add_path(PathInfo.new("UsersController.kt"))

    users.details.code_paths.map(&.path).should contain("UsersController.kt")
    graphql.details.code_paths.map(&.path).should_not contain("UsersController.kt")
  end

  it "skips absolute request URLs with an empty host" do
    endpoints = analyze_postman <<-JSON
      {
        "info": { "name": "Empty Host Collection" },
        "item": [
          { "name": "Empty host", "request": "https:///users" },
          { "name": "Empty host with a port", "request": "https://:443/orders" },
          { "name": "Empty host with a query", "request": "https://?next=/query" },
          {
            "name": "Raw empty host",
            "request": { "method": "GET", "url": { "raw": "https:///raw" } }
          },
          { "name": "Relative request", "request": "/health" }
        ]
      }
      JSON

    endpoints.map(&.url).should eq ["/health"]
  end

  it "keeps raw JSON body params next to unquoted {{var}} values" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {"name": "x", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "item": [{"name": "u", "request": {"method": "PUT", "url": "https://api.example.com/pets",
          "body": {"mode": "raw", "raw": "{\\"name\\": \\"{{n}}\\", \\"age\\": {{age}}, \\"id\\": {{$randomInt}}}"}}}]
      }
      JSON

    endpoints[0].params.select(&.param_type.==("json")).map { |p| {p.name, p.value} }.should eq([{"name", "{{n}}"}, {"age", ""}, {"id", ""}])
  end

  it "keeps the base path a host variable carries in a URL object" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {"name": "x", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "item": [
          {"name": "a", "request": {"method": "GET", "url": "{{baseUrl}}/pets"}},
          {"name": "b", "request": {"method": "DELETE", "url": {"raw": "{{baseUrl}}/pets/:id", "host": ["{{baseUrl}}"], "path": ["pets", ":id"]}}},
          {"name": "c", "request": {"method": "GET", "url": {"host": ["api", "example", "com"], "path": ["users"]}}}
        ],
        "variable": [{"key": "baseUrl", "value": "https://petstore.example.com/v1"}]
      }
      JSON

    endpoints.map(&.url).should eq(["/v1/pets", "/v1/pets/:id", "/users"])
  end

  it "resolves apiUrl from a collection variable when no environment file is present" do
    endpoints = analyze_postman <<-JSON
      {
        "info": {"name": "Conduit", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "variable": [{"key": "apiUrl", "value": "https://conduit.productionready.io/api"}],
        "item": [{"name": "All Articles", "request": {"method": "GET", "url": {"raw": "{{apiUrl}}/articles", "host": ["{{apiUrl}}"], "path": ["articles"]}}}]
      }
      JSON

    endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.should eq(["GET /api/articles"])
  end
end

private def analyze_postman_with_files(files : Hash(String, String)) : Array(Endpoint)
  dir = File.tempname("postman_env")
  Dir.mkdir_p(dir)
  collection = ""
  CodeLocator.instance.clear_all
  files.each do |name, content|
    path = File.join(dir, name)
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
    collection = path if name.ends_with?(".postman_collection.json") || name == "collection.json"
  end
  CodeLocator.instance.push(Noir::LocatorKeys::POSTMAN_JSON, collection)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  Analyzer::Specification::Postman.new(options).analyze
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir
end

describe "Postman environment files" do
  it "applies a sibling environment and lets the collection variable win" do
    collection = <<-JSON
      {
        "info": {"name": "Conduit", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "variable": [{"key": "apiUrl", "value": "https://collection.example/from-collection"}],
        "item": [{"name": "All Articles", "request": {"method": "GET", "url": {"raw": "{{apiUrl}}/articles", "host": ["{{apiUrl}}"], "path": ["articles"]}}}]
      }
      JSON
    environment = <<-JSON
      {"name": "Conduit", "values": [{"enabled": true, "key": "apiUrl", "value": "https://conduit.productionready.io/api"}], "_postman_variable_scope": "environment"}
      JSON

    endpoints = analyze_postman_with_files({
      "Conduit.postman_collection.json"  => collection,
      "Conduit.postman_environment.json" => environment,
    })
    endpoints.map(&.url).should eq(["/from-collection/articles"])
  end

  it "ignores a disabled environment value" do
    collection = <<-JSON
      {
        "info": {"name": "Conduit", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "item": [{"name": "All Articles", "request": {"method": "GET", "url": {"raw": "{{apiUrl}}/articles", "host": ["{{apiUrl}}"], "path": ["articles"]}}}]
      }
      JSON
    environment = <<-JSON
      {"name": "Conduit", "values": [
        {"enabled": true, "key": "apiUrl", "value": "https://conduit.productionready.io/api"},
        {"enabled": false, "key": "apiUrl", "value": "https://evil.example/nope"}
      ], "_postman_variable_scope": "environment"}
      JSON

    endpoints = analyze_postman_with_files({
      "Conduit.postman_collection.json"  => collection,
      "Conduit.postman_environment.json" => environment,
    })
    endpoints.map(&.url).should eq(["/api/articles"])
  end

  it "prefers the environment whose name matches the collection when values disagree" do
    collection = <<-JSON
      {
        "info": {"name": "Conduit", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "item": [{"name": "All Articles", "request": {"method": "GET", "url": {"raw": "{{apiUrl}}/articles", "host": ["{{apiUrl}}"], "path": ["articles"]}}}]
      }
      JSON

    endpoints = analyze_postman_with_files({
      "a.postman_environment.json"      => %({"name": "Other", "values": [{"enabled": true, "key": "apiUrl", "value": "https://a.example/aaa"}]}),
      "b.postman_environment.json"      => %({"name": "Conduit", "values": [{"enabled": true, "key": "apiUrl", "value": "https://b.example/bbb"}]}),
      "Conduit.postman_collection.json" => collection,
    })
    endpoints.map(&.url).should eq(["/bbb/articles"])

    agreed = analyze_postman_with_files({
      "a.postman_environment.json"      => %({"name": "Other", "values": [{"enabled": true, "key": "apiUrl", "value": "https://conduit.productionready.io/api"}]}),
      "b.postman_environment.json"      => %({"name": "Also", "values": [{"enabled": true, "key": "apiUrl", "value": "https://conduit.productionready.io/api"}]}),
      "Conduit.postman_collection.json" => collection,
    })
    agreed.map(&.url).should eq(["/api/articles"])

    unnamed = analyze_postman_with_files({
      "a.postman_environment.json"      => %({"name": "Foo", "values": [{"enabled": true, "key": "apiUrl", "value": "https://a.example/aaa"}]}),
      "b.postman_environment.json"      => %({"name": "Bar", "values": [{"enabled": true, "key": "apiUrl", "value": "https://b.example/bbb"}]}),
      "Conduit.postman_collection.json" => collection,
    })
    unnamed.map(&.url).should eq(["/aaa/articles"])
  end
end
