require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{name}", "GET", [
    Param.new("name", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/users/{name}", "PUT", [
    Param.new("name", "", "path"),
    Param.new("q", "", "query"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/orders", "POST", [
    Param.new("X-Request-Token", "", "header"),
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/keys", "GET"),
  Endpoint.new("/open", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/admin/users/{uid}", "DELETE", [
    Param.new("uid", "", "path"),
  ]),
  Endpoint.new("/reports/daily", "GET", [
    Param.new("day", "", "query"),
  ]),
  # A blueprint's "/" is served at the bare url_prefix.
  Endpoint.new("/reports", "GET"),
]

FunctionalTester.new("fixtures/python/chalice/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Chalice route auth", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags authorizer= and api_key_required=True routes" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/chalice/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    auth = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.select(&.name.==("auth")).map(&.description)
    end

    auth.call("POST", "/orders").should eq ["Protected by Chalice authorizer=authorizer"]
    auth.call("GET", "/keys").should eq ["Protected by Chalice api_key_required=True"]
    auth.call("GET", "/").should be_empty
    auth.call("GET", "/open").should be_empty
  end
end
