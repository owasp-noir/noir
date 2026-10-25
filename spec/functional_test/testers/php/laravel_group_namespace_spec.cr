require "../../func_spec.cr"

# Laravel route groups in the array form:
#   * `'namespace' => ...` qualifies the group's string actions, bare
#     (`'Controller@method'`) or as an action array's `'uses' =>`, and nests
#     relative to the parent group's namespace;
#   * `Route::get('', ...)` is the group prefix itself;
#   * `'middleware' => 'members'` guards when the group, defined in
#     `bootstrap/app.php`, has a member whose `handle()` refuses;
#     `->withoutMiddleware(['members'])` takes it away again, an unrelated
#     `->withoutMiddleware('throttle')` does not;
#   * a FormRequest's own `$this->query('x')` and a trait helper that hands
#     its argument to `$this->get(...)` are request reads; `$request->email`
#     is the dynamic-property read.
describe "Laravel group namespace / group middleware / FormRequest reads", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/laravel_group_namespace/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves namespaced string actions and group guards" do
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

    index = find.call("GET", "/account")
    index.handler.should_not be_nil
    index.handler.not_nil!.name.should eq("AccountController@index")
    index.handler.not_nil!.line.should eq(10)
    guards.call(index).should eq(["Laravel 'members' middleware group (Authenticate)"])
    params.call(index).should eq(["email:query"])

    password = find.call("POST", "/account/password")
    password.handler.not_nil!.name.should eq("AccountController@password")
    guards.call(password).should_not be_empty
    params.call(password).should eq(["current:form", "new:form", "new_confirmation:form", "page:query"])

    guards.call(find.call("GET", "/account/open")).should be_empty
    guards.call(find.call("GET", "/account/throttled")).should_not be_empty

    stats = find.call("GET", "/stats")
    stats.handler.not_nil!.path.to_s.should end_with("app/Http/Controllers/Admin/StatsController.php")
    guards.call(stats).should be_empty
  end
end
