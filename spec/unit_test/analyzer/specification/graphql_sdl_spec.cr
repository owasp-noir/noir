require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/graphql_sdl"

private def analyze_sdl(content : String, path : String = "/tmp/schema.graphql")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "graphql-sdl"
  locator.push "graphql-sdl", path

  options = create_test_options
  analyzer = Analyzer::Specification::GraphqlSdl.new options
  analyzer.analyze
ensure
  File.delete(path) if File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "GraphQL SDL Analyzer" do
  it "emits one endpoint per Query / Mutation / Subscription field" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        ping: String
        echo(message: String!): String
      }

      type Mutation {
        publish(channel: String!, body: String!): Boolean
      }

      type Subscription {
        events: String
      }
      SDL

    endpoints.size.should eq 4
    endpoints.map(&.url).should eq [
      "/graphql#Query.ping",
      "/graphql#Query.echo",
      "/graphql#Mutation.publish",
      "/graphql#Subscription.events",
    ]
    endpoints.all? { |e| e.method == "POST" }.should be_true
    endpoints.find { |e| e.url.includes?("Subscription") }.not_nil!.protocol.should eq "ws"
  end

  it "extracts arguments as json params and embeds an operation document" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        echo(message: String!, times: Int = 1): String
      }
      SDL

    endpoint = endpoints.first
    arg_params = endpoint.params.reject { |p| p.name.starts_with?("graphql_") }
    arg_params.map(&.name).should eq ["message", "times"]
    arg_params.all? { |p| p.param_type == "json" }.should be_true

    doc_param = endpoint.params.find { |p| p.name == "graphql_query_echo" }.not_nil!
    doc_param.value.should contain "$message: String!"
    doc_param.value.should contain "$times: Int"
    doc_param.value.should contain "echo(message: $message, times: $times)"
  end

  it "preserves trailing non-null marker on list types" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        users: [User!]!
      }
      SDL

    return_tags = tag_descriptions(endpoints.first, "graphql-return")
    return_tags.should eq ["[User!]!"]
  end

  it "handles `extend type Query` (federation)" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        ping: String
      }

      extend type Query {
        searchProducts(q: String!): String
      }
      SDL

    endpoints.map(&.url).sort.should eq [
      "/graphql#Query.ping",
      "/graphql#Query.searchProducts",
    ].sort
  end

  it "resolves custom root names via the schema block" do
    endpoints = analyze_sdl <<-SDL
      schema {
        query: MyQueryRoot
        mutation: MyMutationRoot
      }

      type MyQueryRoot {
        ping: String
      }

      type MyMutationRoot {
        publish(body: String!): Boolean
      }
      SDL

    endpoints.map(&.url).sort.should eq [
      "/graphql#Mutation.publish",
      "/graphql#Query.ping",
    ]
    root_tags = endpoints.flat_map { |e| tag_descriptions(e, "graphql-root") }.sort
    root_tags.should eq ["MyMutationRoot", "MyQueryRoot"]
  end

  it "captures @directives as tags" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        legacy: String @deprecated(reason: "Use status instead")
        admin: String @auth(role: "admin")
      }
      SDL

    legacy = endpoints.find { |e| e.url.ends_with?("legacy") }.not_nil!
    auth = endpoints.find { |e| e.url.ends_with?("admin") }.not_nil!

    tag_descriptions(legacy, "graphql-directive").any?(&.starts_with?("@deprecated")).should be_true
    tag_descriptions(auth, "graphql-directive").any?(&.starts_with?("@auth")).should be_true
  end

  it "skips strings containing keywords that look like SDL" do
    endpoints = analyze_sdl <<-SDL
      "type Query { fake: String }"
      type Query {
        real: String
      }
      SDL

    endpoints.map(&.url).should eq ["/graphql#Query.real"]
  end

  it "reports per-field line numbers" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        first: String
        second: String
      }
      SDL

    endpoints[0].details.code_paths.first.line.should eq 2
    endpoints[1].details.code_paths.first.line.should eq 3
  end
end
