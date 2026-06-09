require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/article/", "GET"),
  Endpoint.new("/api/article/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/api/user/", "GET"),
  Endpoint.new("/api/user/{login}", "GET", [Param.new("login", "", "path"), Param.new("lorem", "ipsum", "cookie")]),
  Endpoint.new("/v1", "GET", [Param.new("version", "1", "query")]),
  Endpoint.new("/v2", "GET", [Param.new("version", "2", "query")]),
  Endpoint.new("/version2", "GET", [Param.new("version", "2", "query")]),
  Endpoint.new("/v3", "GET", [Param.new("version", "3", "query")]),
  Endpoint.new("/version3", "GET", [Param.new("version", "3", "query")]),
  Endpoint.new("/article", "POST", [
    Param.new("title", "", "json"),
    Param.new("headline", "", "json"),
    Param.new("content", "", "json"),
    Param.new("author", "", "json"),
    Param.new("slug", "", "json"),
    Param.new("addedAt", "", "json"),
    Param.new("deleted", "", "json"),
  ]),
  Endpoint.new("/article2", "POST", [Param.new("title", "", "query"), Param.new("content", "", "query")]),
  Endpoint.new("/article/{slug}", "GET", [Param.new("slug", "", "path"), Param.new("preview", "false", "query")]),
  Endpoint.new("/article/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/article/{id}", "DELETE", [Param.new("id", "", "path"), Param.new("soft", "", "form"), Param.new("X-Custom-Header", "soft-delete", "header")]),
  Endpoint.new("/article2/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/article/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/request", "GET", [Param.new("type", "basic", "query"), Param.new("X-Custom-Header", "basic", "header")]),
  Endpoint.new("/request", "POST", [Param.new("type", "basic", "query"), Param.new("X-Custom-Header", "basic", "header")]),
  Endpoint.new("/request2", "GET", [Param.new("type", "advanced", "query"), Param.new("X-Custom-Header", "advanced", "header")]),
  Endpoint.new("/request2", "POST", [Param.new("type", "advanced", "query"), Param.new("X-Custom-Header", "advanced", "header")]),
  Endpoint.new("/constant-param", "GET", [Param.new("cursor", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/mcp", "POST"),
  Endpoint.new("/mcp", "GET"),
  Endpoint.new("/mcp", "DELETE"),
]

FunctionalTester.new("fixtures/kotlin/spring/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "--ai-context on Kotlin Spring security annotations" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces Spring Security method annotations as endpoint auth guards" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/constant-param" }
    endpoint.tags.map { |tag| {tag.name, tag.description, tag.tagger} }.should contain({
      "auth",
      "Protected by @PreAuthorize(hasRole('ADMIN'))",
      "kotlin_spring_security_analyzer",
    })

    context = endpoint.ai_context
    context = context.should_not be_nil
    context.guards.map { |guard| {guard.kind, guard.name, guard.source} }.should contain({
      "auth_guard",
      "@PreAuthorize(hasRole('ADMIN'))",
      "kotlin_spring_security_analyzer",
    })
  end

  it "surfaces Spring MVC view-name returns as template rendering sinks" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/v1" }
    context = endpoint.ai_context
    context = context.should_not be_nil

    sink = context.sinks.find { |entry| entry.kind == "template_render" }
    sink.should_not be_nil
    sink.not_nil!.name.should eq("Spring MVC view blog")
    sink.not_nil!.description.to_s.should contain("server-side view name")
  end
end
