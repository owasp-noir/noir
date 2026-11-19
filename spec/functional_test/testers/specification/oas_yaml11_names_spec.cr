require "../../func_spec.cr"

# OpenAPI is YAML 1.2: `on`, `No`, `OFF`, `yes` are names, not booleans.
tester = FunctionalTester.new("fixtures/specification/oas_yaml11_names/", {
  :techs     => 2,
  :endpoints => 3,
}, [
  Endpoint.new("/tiles/{z}", "GET", [
    Param.new("z", "", "path"),
    Param.new("on", "", "query"),
    Param.new("No", "", "query"),
  ]),
  Endpoint.new("/points", "POST", [
    Param.new("x", "", "json"),
    Param.new("on", "", "json"),
    Param.new("OFF", "", "json"),
    Param.new("yes", "", "json"),
  ]),
  Endpoint.new("/legacy", "GET", [
    Param.new("off", "", "query"),
    Param.new("id", "", "query"),
  ]),
])
tester.perform_tests

describe "OpenAPI YAML 1.1 boolean names", tags: "functional" do
  it "reports no true/false params" do
    names = tester.app.endpoints.flat_map(&.params).map(&.name)
    names.should_not contain("true")
    names.should_not contain("false")
  end
end
