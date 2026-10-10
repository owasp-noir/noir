require "../../func_spec.cr"

# Regression test: `filter_input(` / `INPUT_GET,` / `'two',` / `)` (PSR-12
# wrapping of a long call) was missed by the per-line superglobal scan; a
# commented-out wrapped read must still not count.
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("one", "", "query"),
    Param.new("two", "", "query"),
  ]),
  Endpoint.new("/index.php", "POST", [
    Param.new("three", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/php/php_wrapped_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Pure PHP wrapped param negatives", tags: "functional" do
  it "does not read a param out of a commented-out wrapped call" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/php_wrapped_params/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.flat_map(&.params).map(&.name).should_not contain("ghost")
  end
end
