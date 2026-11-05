require "../../func_spec.cr"

# A string action without a group namespace (`'UsersController@index'`, the
# namespace comes from RouteServiceProvider at runtime) still resolves to
# `app/Http/Controllers`, so the constructor's `$this->middleware('auth')`
# guards the route.
describe "Laravel bare controller names", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/laravel_bare_controller/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves the controller and its constructor middleware" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    find = ->(url : String) { app.endpoints.find! { |ep| ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }

    users = find.call("/users")
    users.handler.not_nil!.name.should eq("UsersController@index")
    guards.call(users).should_not be_empty
    guards.call(find.call("/pages")).should be_empty
    # Two controllers answer to `ReportsController`: the route's runtime
    # namespace is unknown, so neither one's middleware is attached.
    reports = find.call("/reports")
    reports.handler.should be_nil
    guards.call(reports).should be_empty
  end
end
