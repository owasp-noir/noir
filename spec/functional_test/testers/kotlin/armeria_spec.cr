require "../../func_spec.cr"

# Armeria annotated services written in Kotlin, mounted by a Kotlin
# `Server.builder()` chain (#3268), including the binding-builder form
# `.annotatedService().pathPrefix("/admin").build(...)`. A private DTO
# field is not a body param, and `LegacyClient.kt` (another library's
# `@Get`, the Armeria package named only in a comment) is not a route.
expected_endpoints = [
  Endpoint.new("/health", "ANY"),
  Endpoint.new("/admin/stats", "GET"),
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
    lines["PUT /users/{userId}"].should eq(16)
  end
end
