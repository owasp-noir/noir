require "../../func_spec.cr"

# Regression test: black wraps a long accessor call over several lines
# (`request.args.get(` / `"q2"` / `)`). The per-line param regexes only
# matched the one-line form, so every wrapped param was dropped.
expected_endpoints = [
  Endpoint.new("/one", "GET", [
    Param.new("q1", "", "query"),
    Param.new("H1", "", "header"),
  ]),
  Endpoint.new("/split", "GET", [
    Param.new("q2", "", "query"),
    Param.new("H2", "", "header"),
    Param.new("c2", "", "cookie"),
  ]),
  Endpoint.new("/split", "POST", [
    Param.new("q2", "", "query"),
    Param.new("f2", "", "form"),
    Param.new("H2", "", "header"),
    Param.new("c2", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/python/flask_wrapped_accessors/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Flask wrapped accessor negatives", tags: "functional" do
  it "does not read a param out of a commented-out wrapped call" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_wrapped_accessors/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.flat_map(&.params).map(&.name).should_not contain("commented")
  end
end
