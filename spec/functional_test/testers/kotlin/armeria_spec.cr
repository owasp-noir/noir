require "../../func_spec.cr"

# Armeria annotated services written in Kotlin, mounted by a Kotlin
# `Server.builder()` chain (#3268).
expected_endpoints = [
  Endpoint.new("/health", "ANY"),
  Endpoint.new("/api/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/items/search", "POST", [Param.new("q", "", "query")]),
  Endpoint.new("/users/{userId}", "PUT", [
    Param.new("X-Request-Id", "", "header"),
    Param.new("dryRun", "false", "query"),
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("userId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/armeria/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Kotlin Armeria code paths", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports the registration line of builder and annotated routes" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/armeria/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    lines = app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.details.code_paths.first.line} }
    lines["ANY /health"].should eq(11)
    lines["GET /api/items/{id}"].should eq(8)
    lines["PUT /users/{userId}"].should eq(14)
  end
end
