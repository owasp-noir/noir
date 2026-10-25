require "../../func_spec.cr"

# Class views resolve like Python: the registered class's MRO (C3) picks the
# verb method, a project `dispatch_request` that doesn't hand back to the
# framework serves every method, and `decorators` / `method_decorators`
# are read off the registered class's MRO, module-level assignments after
# the class body included.
expected_endpoints = [
  Endpoint.new("/page", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/public", "GET"),
  Endpoint.new("/method-guarded", "GET"),
  Endpoint.new("/mixed", "GET"),
  Endpoint.new("/late", "GET"),
  Endpoint.new("/open", "GET"),
  Endpoint.new("/diamond", "GET"),
]

FunctionalTester.new("fixtures/python/flask_class_view_mro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Flask class views by MRO", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads handlers and guards the way Python resolves them" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_class_view_mro/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    rows = app.endpoints.to_h { |ep| {ep.url, ep} }
    rows["/page"].handler.try(&.name).should eq("Page.dispatch_request")
    rows["/diamond"].handler.try(&.name).should eq("Right.get")
    rows["/admin"].handler.try(&.name).should eq("BaseThing.get")

    guards = rows.transform_values { |ep| ep.ai_context.try(&.guards.map(&.kind)) || [] of String }
    %w[/page /admin /method-guarded /mixed /late].each do |url|
      guards[url].should eq(["auth_guard"]), "#{url} should be guarded"
    end
    %w[/public /open /diamond].each do |url|
      guards[url].should be_empty, "#{url} should be open"
    end
  end
end
