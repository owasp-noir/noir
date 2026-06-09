require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/posts", "GET").tap do |ep|
    ep.push_callee(Callee.new("postHandler::all", line: 20))
    ep.push_callee(Callee.new("posts.findAll", line: 43))
  end,

  Endpoint.new("/posts/{id}", "GET", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("postHandler::get", line: 21))
    ep.push_callee(Callee.new("posts.findOne", line: 47))
  end,

  Endpoint.new("/posts", "POST", [Param.new("title", "", "json"), Param.new("content", "", "json")]).tap do |ep|
    ep.push_callee(Callee.new("postHandler::create", line: 22))
    ep.push_callee(Callee.new("posts.save", line: 52))
    ep.push_callee(Callee.new("decorate", line: 54))
    ep.push_callee(Callee.new("posts.findOne", line: 59))
  end,

  Endpoint.new("/posts/{id}", "PUT", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("postHandler::update", line: 23))
    ep.push_callee(Callee.new("posts.update", line: 63))
  end,

  Endpoint.new("/posts/{id}", "DELETE", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("postHandler::delete", line: 24))
    ep.push_callee(Callee.new("posts.delete", line: 68))
  end,

  Endpoint.new("/imported", "GET", [Param.new("id", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("importedPostHandler::show", line: 26))
    ep.push_callee(Callee.new(
      "importedPosts.load",
      "./spec/functional_test/fixtures/kotlin/spring_functional/src/main/kotlin/com/example/handlers/ImportedPostHandler.kt",
      19
    ))
  end,

  Endpoint.new("/constructor-imported", "GET", [Param.new("id", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("importedPostHandler::show", line: 36))
    ep.push_callee(Callee.new(
      "importedPosts.load",
      "./spec/functional_test/fixtures/kotlin/spring_functional/src/main/kotlin/com/example/handlers/ImportedPostHandler.kt",
      19
    ))
  end,

  Endpoint.new("/inline-audit", "GET").tap do |ep|
    ep.push_callee(Callee.new("auditService.record", line: 27))
  end,

  Endpoint.new("/inline-empty", "GET").tap do |ep|
    ep.push_callee(Callee.new("ServerResponse.ok", line: 28))
  end,
]

FunctionalTester.new("fixtures/kotlin/spring_functional/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "--ai-context on Kotlin Spring functional router fixtures" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces functional handler references and handler body callees" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_functional/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/imported" }
    context = endpoint.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("importedPostHandler::show")
    context.callees.map(&.name).should contain("importedPosts.load")
    inline = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/inline-audit" }
    inline_context = inline.ai_context
    inline_context = inline_context.should_not be_nil
    inline_context.callees.map(&.name).should contain("auditService.record")
    empty_inline = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/inline-empty" }
    empty_inline_context = empty_inline.ai_context
    empty_inline_context = empty_inline_context.should_not be_nil
    empty_inline_context.callees.map(&.name).should contain("ServerResponse.ok")
    context.callees.map(&.name).should_not contain("ok")
    context.callees.map(&.name).should_not contain("req.queryParam")
    context.callees.map(&.name).should_not contain("log.info")
    context.callees.map(&.name).should_not contain("UUID.fromString")
    context.callees.map(&.name).should_not contain("Thread.sleep")
    context.callees.map(&.name).should_not contain("Random.nextLong")
    context.callees.map(&.name).should_not contain("let")
  end

  it "does not surface simple Kotlin constructor calls as handler callees" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_functional/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/posts" }
    context = endpoint.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("posts.save")
    context.callees.map(&.name).should contain("decorate")
    context.callees.map(&.name).should contain("posts.findOne")
    context.callees.map(&.name).should_not contain("PostView")
    context.callees.map(&.name).should_not contain("ApiResponse.buildResponse")
    context.callees.map(&.name).should_not contain("view.copy")
    context.callees.map(&.name).should_not contain("model.addAttribute")
    context.callees.map(&.name).should_not contain("resource.add")
    context.callees.map(&.name).should_not contain("results.map")
    context.callees.map(&.name).should_not contain("num.incrementAndGet")
  end
end
