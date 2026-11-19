require "../../func_spec.cr"

line_params = [Param.new("sku", "", "json"), Param.new("quantity", "", "json")]
paging = [Param.new("page", "", "query"), Param.new("size", "", "query"), Param.new("sort", "", "query")]

expected_endpoints = [
  # A body wrapped in a collection or a reactive type binds its element's fields.
  Endpoint.new("/kt/orders/bulk-list", "POST", line_params),
  Endpoint.new("/kt/orders/bulk-array", "POST", line_params),
  Endpoint.new("/kt/orders/mono", "POST", line_params),
  Endpoint.new("/kt/orders/flux", "POST", line_params),
  Endpoint.new("/kt/orders/flow", "POST", line_params),
  Endpoint.new("/kt/orders/entity", "POST", line_params),
  Endpoint.new("/kt/orders/ids", "POST", [Param.new("ids", "", "json")]),
  # Pageable, request-object reads and literal-key reads of a map argument.
  Endpoint.new("/kt/reports", "GET", paging),
  Endpoint.new("/kt/reports/raw", "GET", [Param.new("from", "", "query"), Param.new("X-Tenant", "", "header")]),
  Endpoint.new("/kt/reports/headers", "GET", [Param.new("X-Trace-Id", "", "header")]),
  Endpoint.new("/kt/reports/map", "GET", [Param.new("cursor", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/kt/search", "GET", [Param.new("q", "", "query")] + paging),
  Endpoint.new("/kt/search/form", "POST", [Param.new("token", "", "form")]),
]

FunctionalTester.new("fixtures/kotlin/spring_handler_args/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Kotlin Spring handler arguments: no extra params", tags: "functional" do
  it "emits exactly the expected params per endpoint" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_handler_args/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    expected_endpoints.each do |expected|
      actual = app.endpoints.find! { |ep| ep.method == expected.method && ep.url == expected.url }
      actual.params.map { |p| {p.name, p.param_type} }.should eq(expected.params.map { |p| {p.name, p.param_type} })
    end
  end
end
