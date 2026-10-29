require "../../func_spec.cr"

# #3321: `[Authorize]` / `[AllowAnonymous]` anywhere in an action's attribute
# stack; `MapGet("")` maps the group prefix; a group's own
# `group.RequireAuthorization(...)` statement guards its routes (only in the
# method that declares it); auth chained after a block-bodied lambda.
describe "ASP.NET Core auth shapes", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/csharp/aspnet_auth_shapes/#{fixture}/")])
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

  it "reads attributes past a long attribute stack and route-group statements" do
    endpoints = scan.call("app")
    guarded.call(endpoints, "POST", "/Users/{userId}/Images/{index}").should be_true
    guarded.call(endpoints, "GET", "/Admin/Ping").should be_false
    guarded.call(endpoints, "GET", "/Admin/Stats").should be_true
    guarded.call(endpoints, "GET", "/organizations/{orgId}/access-rules").should be_true
    guarded.call(endpoints, "GET", "/organizations/{orgId}/access-rules/{id}").should be_true
    guarded.call(endpoints, "DELETE", "/organizations/{orgId}/access-rules/{id}").should be_true
    guarded.call(endpoints, "GET", "/public/status").should be_false
  end

  it "maps empty patterns and reads auth chained after a block lambda" do
    endpoints = scan.call("local")
    guarded.call(endpoints, "GET", "/rules").should be_true
    guarded.call(endpoints, "POST", "/rules").should be_true
    guarded.call(endpoints, "DELETE", "/rules/{id}").should be_false
    guarded.call(endpoints, "POST", "/notes").should be_true
  end
end
