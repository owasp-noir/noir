require "../../func_spec.cr"

# TanStack Start server routes: `createFileRoute(...)({ server: { handlers } })`
# serves one endpoint per verb key, as an object or through
# `createHandlers({ DELETE: { middleware, handler } })`. A handlers-only
# route has no page, so `/api/users/:id` serves no GET.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/users/:id", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/typescript/tanstack_start_server_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "TanStack Start server route lines", tags: "functional" do
  it "reports each verb at its handler key" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/tanstack_start_server_routes/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }.details.code_paths.first.line.should eq(11)
    app.endpoints.find! { |ep| ep.method == "DELETE" }.details.code_paths.first.line.should eq(7)
  end
end
