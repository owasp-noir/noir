require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/new", "GET"),
  # `(marketing)` is a route group — stripped from the URL.
  Endpoint.new("/about", "GET"),
  Endpoint.new("/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # Fallback: no explicit verb exports → GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/api/auth", "GET"),
  Endpoint.new("/api/auth", "POST"),
  Endpoint.new("/api/auth", "PUT"),
  Endpoint.new("/api/auth", "DELETE"),
  Endpoint.new("/api/auth", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/sveltekit/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "SvelteKit route source attribution" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "uses exported API handler lines" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/sveltekit/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    users_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users" }
    users_get.details.code_paths.first.line.should eq(3)

    users_post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    users_post.details.code_paths.first.line.should eq(9)

    user_put = app.endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/api/users/{id}" }
    user_put.details.code_paths.first.line.should eq(5)

    user_delete = app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/api/users/{id}" }
    user_delete.details.code_paths.first.line.should eq(10)
  end
end
