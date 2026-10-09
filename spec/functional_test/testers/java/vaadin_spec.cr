require "../../func_spec.cr"

expected_endpoints = [
  # Flow views.
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/app/dashboard", "GET"),
  Endpoint.new("/app/home", "GET"),
  Endpoint.new("/login", "GET"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/reports", "GET"),
  Endpoint.new("/greet/{name}/{id}", "GET", [Param.new("name", "", "path"), Param.new("id", "", "path")]),
  Endpoint.new("/product/{parameter}", "GET", [Param.new("parameter", "", "path")]),
  # Same-file constant value, comment inside the annotation.
  Endpoint.new("/app/settings", "GET"),
  # Hilla browser-callable services.
  Endpoint.new("/connect/UserEndpoint/findUser", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/connect/UserEndpoint/deleteUser", "POST", [Param.new("id", "", "json"), Param.new("hard", "", "json")]),
  Endpoint.new("/connect/orders/list", "POST"),
  # Inherited from Hilla's CrudRepositoryService.
  Endpoint.new("/connect/PersonService/list", "POST", [Param.new("pageable", "", "json"), Param.new("filter", "", "json")]),
  Endpoint.new("/connect/PersonService/get", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/connect/PersonService/exists", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/connect/PersonService/count", "POST", [Param.new("filter", "", "json")]),
  Endpoint.new("/connect/PersonService/save", "POST", [Param.new("value", "", "json")]),
  Endpoint.new("/connect/PersonService/saveAll", "POST", [Param.new("values", "", "json")]),
  Endpoint.new("/connect/PersonService/delete", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/connect/PersonService/deleteAll", "POST", [Param.new("ids", "", "json")]),
]

# java_spring + java_vaadin. The actuator @Endpoint, the static and the
# private service methods yield nothing.
FunctionalTester.new("fixtures/java/vaadin/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Vaadin access annotations", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags endpoints from @AnonymousAllowed / @PermitAll / @RolesAllowed" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/vaadin/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map(&.name)
    end

    tags.call("POST", "/connect/UserEndpoint/findUser").should eq ["anonymous"]
    tags.call("POST", "/connect/UserEndpoint/deleteUser").should eq ["auth"]
    tags.call("POST", "/connect/orders/list").should eq ["auth"]
    tags.call("POST", "/connect/PersonService/save").should eq ["anonymous"]
    tags.call("GET", "/login").should eq ["anonymous"]
    tags.call("GET", "/app/dashboard").should eq ["auth"]
    tags.call("GET", "/admin/users").should be_empty
  end
end
