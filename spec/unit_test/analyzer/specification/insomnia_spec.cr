require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/insomnia"

private def analyze_insomnia_json(content : String)
  path = File.tempname("insomnia", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "insomnia-json"
  locator.clear "insomnia-yaml"
  locator.push "insomnia-json", path

  options = create_test_options
  analyzer = Analyzer::Specification::Insomnia.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "insomnia-json"
  locator.clear "insomnia-yaml"
  File.delete(path) if path && File.exists?(path)
end

private def analyze_insomnia_yaml(content : String)
  path = File.tempname("insomnia", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "insomnia-json"
  locator.clear "insomnia-yaml"
  locator.push "insomnia-yaml", path

  options = create_test_options
  analyzer = Analyzer::Specification::Insomnia.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "insomnia-json"
  locator.clear "insomnia-yaml"
  File.delete(path) if path && File.exists?(path)
end

describe "Insomnia Analyzer" do
  it "does not share details between v4 requests in one export" do
    endpoints = analyze_insomnia_json <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": [
          {
            "_id": "req_1",
            "_type": "request",
            "name": "Users",
            "method": "GET",
            "url": "/users"
          },
          {
            "_id": "req_2",
            "_type": "request",
            "name": "GraphQL",
            "method": "POST",
            "url": "/graphql"
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

  it "does not drop requests whose body is a raw string (legacy exports)" do
    endpoints = analyze_insomnia_json <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": [
          {
            "_id": "req_1",
            "_type": "request",
            "name": "Create User",
            "method": "POST",
            "url": "https://api.example.com/users",
            "body": "{\\"foo\\": \\"bar\\"}"
          },
          {
            "_id": "req_2",
            "_type": "request",
            "name": "Plain Body",
            "method": "POST",
            "url": "https://api.example.com/notes",
            "body": "Hello World!"
          }
        ]
      }
      JSON

    endpoints.map(&.url).sort!.should eq ["/notes", "/users"]
    users = endpoints.find!(&.url.==("/users"))
    users.params.map { |p| {p.name, p.param_type} }.should contain({"foo", "json"})

    notes = endpoints.find!(&.url.==("/notes"))
    notes.params.should be_empty
  end

  it "fully expands composite environment variables in URLs" do
    endpoints = analyze_insomnia_json <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": [
          {
            "_id": "env_base",
            "_type": "environment",
            "name": "Base",
            "data": { "base_url": "{{ scheme }}://{{ host }}{{ base_path }}" }
          },
          {
            "_id": "env_values",
            "_type": "environment",
            "name": "Values",
            "data": { "scheme": "https", "host": "api.example.com", "base_path": "/v2" }
          },
          {
            "_id": "req_1",
            "_type": "request",
            "name": "Pet",
            "method": "GET",
            "url": "{{ base_url }}/pet/{{ petId }}"
          }
        ]
      }
      JSON

    endpoints.size.should eq 1
    endpoint = endpoints.first
    endpoint.url.should eq "/v2/pet/:petId"
    endpoint.params.map(&.name).should contain("petId")
    endpoint.params.map(&.name).should_not contain("host")
    endpoint.params.map(&.name).should_not contain("base_path")
  end

  it "does not share details between v5 requests in one collection" do
    endpoints = analyze_insomnia_yaml <<-YAML
      type: collection.insomnia.rest/5.0
      name: Details Collection
      collection:
        - name: Users
          method: GET
          url: /users
        - name: GraphQL
          method: POST
          url: /graphql
      YAML

    users = endpoints.find!(&.url.==("/users"))
    graphql = endpoints.find!(&.url.==("/graphql"))

    users.details.add_path(PathInfo.new("UsersController.kt"))

    users.details.code_paths.map(&.path).should contain("UsersController.kt")
    graphql.details.code_paths.map(&.path).should_not contain("UsersController.kt")
  end
end
