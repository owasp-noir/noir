require "../../func_spec.cr"

describe "--ai-context JS framework callee coverage" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "populates Fastify callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/fastify_callees/")

    context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/users/:id" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("parseUser")
    context.callees.map(&.name).should contain("serviceFactory().save")
  end

  it "populates Express Parse Server callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/express_parse_server_callees/")

    context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/push_audiences" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("parseAudience")
    context.callees.map(&.name).should contain("AudienceService.create")
  end

  it "populates Fastify route-config callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/fastify_route_config/")

    context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/single" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("reply.send")
    context.callees.map(&.name).should contain("statusService.single")
  end

  it "populates Hono callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/hono_callees/")

    context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/users/:id" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("parseUser")
    context.callees.map(&.name).should contain("serviceFactory().save")
  end

  it "populates Hono app.on array callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/hono_on_array/")

    context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/items/:id" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("c.json")
    context.callees.map(&.name).should contain("itemService.lookup")
  end

  it "populates Hono chained middleware callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/hono_chained_middleware/")

    context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/todos" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("c.req.json")
    context.callees.map(&.name).should contain("todoService().add")
  end

  it "populates Koa callees without --include-callee" do
    endpoints = analyze_js_fixture_with_ai_context("fixtures/javascript/koa_callees/")

    context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/users/:id" }.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("parseBody")
    context.callees.map(&.name).should contain("serviceFactory().save")
  end
end

private def analyze_js_fixture_with_ai_context(fixture_path : String) : Array(Endpoint)
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
  options["ai_context"] = YAML::Any.new(true)
  options["nolog"] = YAML::Any.new(true)

  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints
end
