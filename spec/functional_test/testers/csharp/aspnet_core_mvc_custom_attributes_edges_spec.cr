require "../../func_spec.cr"

# Two projects each define `ApiRouteAttribute` (alpha/ vs beta/): a usage takes
# its own project's. A filter with a `Template` property routes nothing. Property
# assignments (`Order = 2`) are not constructor arguments. A comma in a parameter
# list is not an attribute list.
expected_endpoints = [
  Endpoint.new("/alpha/users", "GET"),
  Endpoint.new("/beta/orders", "GET"),
  Endpoint.new("/find", "POST"),
  Endpoint.new("/things/ord", "GET"),
  Endpoint.new("/things", "GET"),
  Endpoint.new("/lookup", "POST", [Param.new("ids", "", "form"), Param.new("marker", "", "form")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_custom_attributes_edges/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "custom route attribute edges", tags: "functional" do
  it "keeps the unresolved-route tag on a non-literal custom verb argument" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/csharp/aspnet_core_mvc_custom_attributes_edges/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    item = app.endpoints.find! { |e| e.url == "/things" }
    item.tags.map(&.name).should contain("unresolved-route")
    app.endpoints.find! { |e| e.url == "/things/ord" }.tags.map(&.name).should_not contain("unresolved-route")
  end
end
