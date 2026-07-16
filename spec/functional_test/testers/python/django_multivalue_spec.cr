require "../../func_spec.cr"

# Regression test: Django QueryDict exposes `getlist("key")` for repeated
# keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/search/", "GET", [
    Param.new("tags", "", "query"),
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/django_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Django multi-value accessor negatives" do
  it "does not report dynamic keys as params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/django_multivalue/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/search/" }
    names = endpoint.params.map(&.name)
    names.should_not contain("some_key")
    names.should_not contain("dynamic")
  end
end
