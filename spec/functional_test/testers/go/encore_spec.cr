require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello/:name", "GET", [Param.new("name", "", "path")]),
  # No path or method and no request struct: /<package>.<Func> on GET and POST.
  Endpoint.new("/hello.Ping", "GET"),
  Endpoint.new("/hello.Ping", "POST"),
  # `raw` without a method accepts any method.
  Endpoint.new("/webhooks/*rest", "ANY", [Param.new("rest", "", "path")]),
  # The `!fallback` route is reported as a `*fallback` wildcard.
  Endpoint.new("/*fallback", "GET", [Param.new("fallback", "", "path")]),
  # Request struct in another file of the package; GET sends untagged fields as snake_case query.
  Endpoint.new("/users", "GET", [
    Param.new("limit", "", "query"),
    Param.new("cursor", "", "query"),
    Param.new("X-Tenant", "", "header"),
    # `json:"-"` drops only a JSON-body field.
    Param.new("Authorization", "", "header"),
    Param.new("offset", "", "query"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  Endpoint.new("/users/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  # A request payload and no method defaults to POST.
  Endpoint.new("/users.Create", "POST", [
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  # `*shared.Other` is not the package's own `Other` struct.
  Endpoint.new("/users/import", "POST"),
]

FunctionalTester.new("fixtures/go/encore/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Encore Go access tags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags access and auth from the directive" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/encore/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map { |tag| {tag.name, tag.description} }
    end

    tags.call("GET", "/hello/:name").should eq [{"encore-access", "public"}]
    tags.call("GET", "/users").should contain({"auth", "Encore auth endpoint"})
    tags.call("POST", "/users.Create").should eq [{"encore-access", "private"}]
  end
end
