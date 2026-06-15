require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/graphql_sdl"

private def analyze_sdl(content : String, path : String? = nil)
  sdl_path = path || File.tempname("noir_graphql_sdl_", ".graphql")
  File.write(sdl_path, content)
  locator = CodeLocator.instance
  locator.clear "graphql-sdl"
  locator.push "graphql-sdl", sdl_path

  options = create_test_options
  analyzer = Analyzer::Specification::GraphqlSdl.new options
  analyzer.analyze
ensure
  CodeLocator.instance.clear "graphql-sdl"
  File.delete(sdl_path) if sdl_path && File.exists?(sdl_path)
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
    endpoints.find!(&.url.includes?("Subscription")).protocol.should eq "ws"
  end

  it "extracts arguments as json params and embeds an operation document" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        echo(message: String!, times: Int = 1): String
      }
      SDL

    endpoint = endpoints.first
    arg_params = endpoint.params.reject(&.name.starts_with?("graphql_"))
    arg_params.map(&.name).should eq ["message", "times"]
    arg_params.all? { |p| p.param_type == "json" }.should be_true

    doc_param = endpoint.params.find! { |p| p.name == "graphql_query_echo" }
    doc_param.value.should contain "$message: String!"
    doc_param.value.should contain "$times: Int"
    doc_param.value.should contain "echo(message: $message, times: $times)"
  end

  it "expands input object arguments into request body fields" do
    endpoints = analyze_sdl <<-SDL
      type Mutation {
        createArticle(input: CreateArticleInput!): Article
        createKaomoji(tags: [TagInput!]!): Kaomoji
      }

      input CreateArticleInput {
        title: String!
        content: String!
        userId: ID!
      }

      input TagInput {
        label: String!
      }
      SDL

    create_article = endpoints.find! { |endpoint| endpoint.url == "/graphql#Mutation.createArticle" }
    create_article.params.reject(&.name.starts_with?("graphql_")).map(&.name).should eq([
      "title",
      "content",
      "userId",
    ])

    create_kaomoji = endpoints.find! { |endpoint| endpoint.url == "/graphql#Mutation.createKaomoji" }
    create_kaomoji.params.reject(&.name.starts_with?("graphql_")).map(&.name).should eq([
      "tags.label",
    ])
    create_kaomoji.params.find! { |param| param.name == "tags.label" }.tags.map(&.name).should contain("graphql-input-field")
  end

  it "expands input fields declared on a single line" do
    # Regression: the field-type character class previously included `\s`,
    # so the type group swallowed the following field on a compact one-line
    # input body — dropping every field after the first and garbling its type.
    endpoints = analyze_sdl <<-SDL
      type Mutation {
        createArticle(input: CreateArticleInput!): Article
      }

      input CreateArticleInput { title: String!  content: String  userId: ID! }
      SDL

    create_article = endpoints.find! { |endpoint| endpoint.url == "/graphql#Mutation.createArticle" }
    create_article.params.reject(&.name.starts_with?("graphql_")).map(&.name).should eq([
      "title",
      "content",
      "userId",
    ])
  end

  it "parses fields whose arguments carry directives with parentheses" do
    # Regression: the cursor was advanced to the first `)` after the argument
    # list opened, but an argument's own directive (`@length(min: 1)`,
    # `@deprecated(reason: ...)`) closes a paren first. That dropped the field
    # (FN) and misread following argument names as fields (FP, e.g. `newArg`).
    endpoints = analyze_sdl <<-SDL
      type Query {
        directiveArg(arg: String! @length(min: 1, max: 255, message: "x")): String
        withDeprecatedArg(oldArg: Int @deprecated(reason: "old"), newArg: Int): String
        plain: String
      }
      SDL

    endpoints.map(&.url).should eq [
      "/graphql#Query.directiveArg",
      "/graphql#Query.withDeprecatedArg",
      "/graphql#Query.plain",
    ]
    # `oldArg` / `newArg` are arguments, not fields — they must not leak as endpoints.
    endpoints.map(&.url).any?(&.includes?("newArg")).should be_false

    with_args = endpoints.find!(&.url.ends_with?("withDeprecatedArg"))
    with_args.params.reject(&.name.starts_with?("graphql_")).map(&.name).should eq ["oldArg", "newArg"]
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

    endpoints.map(&.url).sort!.should eq [
      "/graphql#Query.ping",
      "/graphql#Query.searchProducts",
    ].sort!
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

    endpoints.map(&.url).sort!.should eq [
      "/graphql#Mutation.publish",
      "/graphql#Query.ping",
    ]
    root_tags = endpoints.flat_map { |e| tag_descriptions(e, "graphql-root") }.sort!
    root_tags.should eq ["MyMutationRoot", "MyQueryRoot"]
  end

  it "captures @directives as tags" do
    endpoints = analyze_sdl <<-SDL
      type Query {
        legacy: String @deprecated(reason: "Use status instead")
        admin: String @auth(role: "admin")
      }
      SDL

    legacy = endpoints.find!(&.url.ends_with?("legacy"))
    auth = endpoints.find!(&.url.ends_with?("admin"))

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
