require "../../func_spec.cr"

# What an agent tracing a Symfony route needs from it:
#   * handler: the controller method's definition line, also for a YAML route
#     whose `controller:` names it;
#   * auth: `#[IsGranted('PUBLIC_ACCESS')]` grants everyone; a non-public
#     IsGranted on the method or the class guards; so does an `isGranted()` +
#     AccessDenied helper inherited from the parent; otherwise the first
#     matching `access_control` rule decides, unless the firewall the path
#     lands in has `security: false`; NelmioApiDoc's `#[Security(name: ...)]`
#     only documents a scheme;
#   * params: a bound form's `buildForm` fields (buttons and disabled fields
#     carry no input), same-class helpers' request reads, and the form a
#     `forward()`ed controller submits from the JSON body;
#   * `class: User::class` in an attribute does not make a method route a
#     class prefix.
describe "Symfony handler / access_control auth / form params", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/symfony_trust/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves what serves each route and who may call it" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
    find = ->(method : String, url : String) { endpoints.find! { |ep| ep.method == method && ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }
    params = ->(ep : Endpoint) { ep.params.map { |p| "#{p.name}:#{p.param_type}" }.sort! }

    feed = find.call("GET", "/feed/{token}")
    guards.call(feed).should be_empty
    handler = feed.handler.should_not be_nil
    handler.name.should eq("EntryController::feed")
    handler.path.to_s.should end_with("src/Controller/EntryController.php")
    handler.line.should eq(17)
    guards.call(find.call("GET", "/share/{uid}")).should be_empty

    list = find.call("GET", "/list/{page}")
    guards.call(list).should eq(["Symfony #[IsGranted('LIST')]"])
    params.call(list).should eq(["filter:query", "page:path", "sort:query"])

    home = find.call("GET", "/{page}")
    home.handler.try(&.name).should eq("EntryController::list")
    home.handler.try(&.line).should eq(31)
    guards.call(home).should eq(["Symfony #[IsGranted('LIST')]"])
    params.call(home).should eq(["filter:query", "page:path", "sort:query"])

    edit = find.call("POST", "/edit/{id}")
    guards.call(edit).should eq(["Symfony access_control (ROLE_USER)"])
    params.call(edit).should eq(["attachment:file", "id:path", "title:form"])

    update = find.call("PUT", "/public/items/{id}")
    guards.call(update).should eq(["Symfony isGranted('IS_AUTHENTICATED_FULLY') check"])
    params.call(update).should eq(["id:path", "text:json"])

    guards.call(find.call("GET", "/public/ping")).should be_empty
    guards.call(find.call("GET", "/_profiler/info")).should be_empty
    guards.call(find.call("GET", "/public/stats")).should eq(["Symfony #[IsGranted('ROLE_ADMIN')]"])
  end
end
