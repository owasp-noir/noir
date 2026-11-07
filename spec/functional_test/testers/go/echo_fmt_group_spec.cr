require "../../func_spec.cr"

# `Group(fmt.Sprintf("/%s", strings.ToLower(name)))` keeps the parent
# prefix and names the dynamic segment. `GET ""` must not collapse to
# `/`, or the admin middleware is reported on the public home route.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/admin/entity/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/admin/entity/{name}/add", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/admin/entity/{name}/:id/edit", "GET", [
    Param.new("name", "", "path"),
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/go/echo_fmt_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "echo fmt.Sprintf group middleware stays on that group", tags: "functional" do
  it "tags the dynamic admin routes and not GET /" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/echo_fmt_group/")])
    options["nolog"] = YAML::Any.new(true)
    options["use_taggers"] = YAML::Any.new("go_auth")

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    home = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/" }
    home.tags.any? { |tag| tag.name == "auth" || tag.name == "authz" }.should be_false

    add = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/admin/entity/{name}/add" }
    add.tags.any? { |tag| tag.name == "auth" || tag.name == "authz" }.should be_true
  end
end
