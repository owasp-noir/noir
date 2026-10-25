require "../../func_spec.cr"

# Resource verbs inherited from a project base class, a route rule wrapped
# in a helper that returns it unchanged by default (and one that always
# rewrites it, which is not emitted), and request params read through
# helpers: a two-hop `partial` wrapper reading `request.args`, a JSON body
# handed to a key-checking helper or funcy's `project`, a WTForms form
# bound to `request.form`, and a `"key" in request.form` test.
expected_endpoints = [
  Endpoint.new("/items", "GET", [Param.new("q", "", "query"), Param.new("order", "", "query")]),
  Endpoint.new("/items", "POST", [Param.new("name", "", "json"), Param.new("kind", "", "json")]),
  Endpoint.new("/users/<user_id>", "POST", [
    Param.new("email", "", "json"),
    Param.new("display_name", "", "json"),
    Param.new("user_id", "", "path"),
  ]),
  Endpoint.new("/open", "GET"),
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST", [
    Param.new("remember", "", "form"),
    Param.new("email", "", "form"),
    Param.new("password", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/python/flask_restful_inherited/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "flask-restful inherited handlers and decorators", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads the inherited verb's handler and the class decorators built on a base's" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_restful_inherited/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    rows = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep}
    end
    rows["GET /items"].handler.try(&.name).should eq("BaseListResource.get")
    guards = rows.transform_values { |ep| ep.ai_context.try(&.guards.map(&.kind)) || [] of String }
    guards["GET /items"].should eq(["auth_guard"])
    guards["POST /users/<user_id>"].should eq(["auth_guard"])
    guards["GET /open"].should be_empty
  end
end
