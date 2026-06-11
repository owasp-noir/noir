require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
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
  # No explicit verb exports → falls back to GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/astro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Astro route source attribution" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "uses exported API handler lines" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/astro/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    users_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users" }
    users_get.details.code_paths.first.line.should eq(3)

    users_post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    users_post.details.code_paths.first.line.should eq(9)

    user_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users/{id}" }
    user_get.details.code_paths.first.line.should eq(3)

    user_put = app.endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/api/users/{id}" }
    user_put.details.code_paths.first.line.should eq(7)
  end
end
