require "../../func_spec.cr"

# A project's own route attributes are read from their definitions:
# `[V3ApiController("tag")]` -> `api/v3/tag` (constructor chain + interpolated
# `Template`), `[RestGetById]` -> GET `{id:int}`, `[RestPutById]` -> PUT,
# `[RestPostById]` -> POST. Attributed actions of the abstract generic base
# classes belong to every controller deriving from them, except the ones the
# controller redeclares. A marker attribute that only has a `Template`
# property routes nothing.
expected_endpoints = [
  Endpoint.new("/api/v3/tag", "GET"),
  Endpoint.new("/api/v3/tag/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v3/tag", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/tag", "POST", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/tag/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v3/Series/{id}", "GET", [Param.new("id", "", "path"), Param.new("includeImages", "", "query")]),
  Endpoint.new("/api/v3/Series/lookup", "GET", [Param.new("term", "", "query")]),
  Endpoint.new("/api/v3/Series", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/Series", "POST", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/Series/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v5/calendar", "GET"),
  Endpoint.new("/api/v3/ping", "GET"),
  Endpoint.new("/label", "GET"),
  Endpoint.new("/other", "GET"),
  Endpoint.new("/shared", "GET"),
  Endpoint.new("/refusing/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/refusing", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/refusing", "POST", [Param.new("resource", "", "json")]),
  Endpoint.new("/refusing/me", "GET"),
  Endpoint.new("/api/v3/adv/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v3/adv/plain", "GET"),
  Endpoint.new("/api/v3/adv/after-string", "GET"),
  Endpoint.new("/secure/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/secure", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/secure", "POST", [Param.new("resource", "", "json")]),
  Endpoint.new("/open/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/open", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/open", "POST", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/public/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v3/public", "PUT", [Param.new("resource", "", "json")]),
  Endpoint.new("/api/v3/public", "POST", [Param.new("resource", "", "json")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_custom_attributes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# The `FallbackPolicy` sits in the host project; the API controllers sit in
# projects the host references, so they are behind it. `[AllowAnonymous]`
# still lifts it, and a project the host does not reference stays untouched.
describe "ASP.NET Core FallbackPolicy across referenced projects", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/csharp/#{fixture}/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end
  guarded = ->(endpoints : Array(Endpoint), method : String, url : String) do
    ep = endpoints.find! { |e| e.method == method && e.url == url }
    !(ep.ai_context.try(&.guards.empty?) || ep.ai_context.nil?)
  end

  it "guards referenced projects' controllers, but not an anonymous action or an unreferenced project" do
    endpoints = scan.call("aspnet_core_mvc_custom_attributes")
    guarded.call(endpoints, "GET", "/api/v3/tag").should be_true
    guarded.call(endpoints, "DELETE", "/api/v3/tag/{id}").should be_true
    guarded.call(endpoints, "GET", "/api/v3/ping").should be_false
    guarded.call(endpoints, "GET", "/other").should be_false
  end

  it "lets the owning controller's attributes govern the actions it inherits" do
    endpoints = scan.call("aspnet_core_mvc_custom_attributes")
    guarded.call(endpoints, "GET", "/secure/{id}").should be_true
    guarded.call(endpoints, "POST", "/secure").should be_true
    guarded.call(endpoints, "GET", "/open/{id}").should be_false
    guarded.call(endpoints, "GET", "/api/v3/public/{id}").should be_false
    guarded.call(endpoints, "POST", "/api/v3/public").should be_false
    guarded.call(endpoints, "GET", "/api/v3/tag/{id}").should be_true
    # The controller's body refusal is its own action's; the inherited ones are open.
    guarded.call(endpoints, "GET", "/refusing/me").should be_true
    guarded.call(endpoints, "GET", "/refusing/{id}").should be_false
    guarded.call(endpoints, "POST", "/refusing").should be_false
  end

  it "leaves a library open when a second host serves it without the policy" do
    endpoints = scan.call("aspnet_core_mvc_custom_attributes")
    guarded.call(endpoints, "GET", "/shared").should be_false
  end
end
