require "../../func_spec.cr"

# Regression test: Bottle MultiDicts expose `getall`/`getone` for repeated
# keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/tags", "POST", [
    Param.new("tag", "", "form"),
    Param.new("name", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/bottle_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Bottle multi-value accessor negatives" do
  it "does not report dict-API methods as params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/bottle_multivalue/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/tags" }
    names = endpoint.params.map(&.name)
    names.should_not contain("all_keys")
    names.should_not contain("keys")
  end
end
