require "../../func_spec.cr"

# A verb attribute whose route is a constant (`[HttpGet(ApiRoutes.X)]`) is
# reported at the controller route and tagged `unresolved-route`; the string
# literal of a sibling attribute (`Authorize("Admin")`) is never its route.
expected_endpoints = [
  Endpoint.new("/api/Reports", "GET"),
  Endpoint.new("/api/Reports", "POST"),
  Endpoint.new("/api/Reports", "DELETE"),
  Endpoint.new("/api/Reports/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_unresolved_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "ASP.NET Core MVC unresolved route tags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags only the actions whose route is a constant" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/csharp/aspnet_core_mvc_unresolved_routes/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map(&.name)
    end

    tags.call("GET", "/api/Reports").should eq ["unresolved-route"]
    tags.call("POST", "/api/Reports").should eq ["unresolved-route"]
    tags.call("DELETE", "/api/Reports").should eq ["unresolved-route"]
    tags.call("GET", "/api/Reports/{id}").should be_empty
    app.endpoints.map(&.url).should_not contain("/Admin")
  end
end
