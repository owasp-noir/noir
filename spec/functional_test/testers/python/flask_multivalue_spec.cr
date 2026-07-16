require "../../func_spec.cr"

# Regression test: Werkzeug request MultiDicts expose `getlist("key")` for
# repeated keys (`?tags=a&tags=b`) alongside `get`. The param extractor
# previously matched only `.get(`, so `getlist` params were missed.
expected_endpoints = [
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("tags", "", "query"),
  ]),
  Endpoint.new("/bulk", "POST", [
    Param.new("names", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/python/flask_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Flask multi-value accessor negatives" do
  it "does not report dynamic keys or dict-API methods as params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_multivalue/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/search" }
    names = endpoint.params.map(&.name)
    names.should_not contain("user_supplied_key")
    names.should_not contain("all_keys")
    names.should_not contain("keys")
  end
end
