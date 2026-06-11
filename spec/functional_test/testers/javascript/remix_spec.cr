require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  # `_auth.login.tsx` — pathless layout `_auth` strips from URL.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/login", "PUT"),
  Endpoint.new("/login", "PATCH"),
  Endpoint.new("/login", "DELETE"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users", "PUT"),
  Endpoint.new("/api/users", "PATCH"),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/{splat}", "GET", [Param.new("splat", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/remix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Remix route source attribution" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "uses loader and action handler lines" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/remix/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    api_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users" }
    api_get.details.code_paths.first.line.should eq(3)

    api_post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    api_post.details.code_paths.first.line.should eq(7)

    user_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/users/{id}" }
    user_get.details.code_paths.first.line.should eq(3)

    user_delete = app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/users/{id}" }
    user_delete.details.code_paths.first.line.should eq(7)
  end
end
