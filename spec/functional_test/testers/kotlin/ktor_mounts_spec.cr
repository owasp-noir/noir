require "../../func_spec.cr"

# Routes declared in a `fun Route.x()` live under the prefix the function is
# called at, through any chain of such functions. A function called nowhere,
# or only where the prefix is unknown, keeps the URL its routes spell.
expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/{year}/sign", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/{year}/vote", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/{year}/v2/sign", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/{year}/v2/vote", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/api/admin", "GET"),
  Endpoint.new("/api/public", "GET"),
  Endpoint.new("/api/maybe", "GET"),
  Endpoint.new("/shared", "GET"),
  Endpoint.new("/v1/shared", "GET"),
  Endpoint.new("/free", "GET"),
  Endpoint.new("/orphan", "GET"),
  # Each module's own call site wins for its own `fun Route.api()`; a
  # function only called from another module takes that module's site.
  Endpoint.new("/alpha/ping", "GET"),
  Endpoint.new("/beta/ping", "GET"),
  Endpoint.new("/alpha/lib", "GET"),
]

FunctionalTester.new("fixtures/kotlin/ktor_mounts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# A call inside a non-optional `authenticate { }` guards what it mounts; a
# sibling mounted under the same `route()` prefix stays open.
describe "Ktor mounted route guards", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards only routes mounted inside authenticate" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/ktor_mounts/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guards = ->(url : String) do
      endpoint = app.endpoints.find { |item| item.method == "GET" && item.url == url }
      fail("missing GET #{url}") unless endpoint
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards.call("/api/admin").should eq(["Protected by Ktor authenticate(\"admin\") block"])
    guards.call("/api/public").should be_empty
    guards.call("/api/maybe").should be_empty
    guards.call("/{year}/sign").should be_empty
  end
end
