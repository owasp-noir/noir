require "../../func_spec.cr"

# Request reads the Next.js analyzer takes params from:
#   * App Router: Next 15's `await headers()` / `(await cookies()).get`,
#     `request.cookies.get`, a `searchParams` alias and `formData.getAll`;
#   * Pages Router: `const { query: { page } } = req`, a first argument
#     named `request`, destructures with defaults or renames, and
#     `const { query, body } = req` (the `api-routes-rest` example).
expected_endpoints = [
  Endpoint.new("/api/webhook", "POST", [
    Param.new("stripe-signature", "", "header"),
    Param.new("idempotency-key", "", "header"),
    Param.new("theme", "", "cookie"),
    Param.new("session", "", "cookie"),
    Param.new("dryRun", "", "query"),
    Param.new("tags", "", "form"),
  ]),
  Endpoint.new("/api/auth/{*nextauth}", "GET", [Param.new("nextauth", "", "path")]),
  Endpoint.new("/api/auth/{*nextauth}", "POST", [Param.new("nextauth", "", "path")]),
  Endpoint.new("/api/nested", "GET", [Param.new("page", "", "query"), Param.new("sort", "", "query")]),
  Endpoint.new("/api/request-named", "POST", [
    Param.new("q", "", "query"),
    Param.new("title", "", "body"),
    Param.new("x-token", "", "header"),
    Param.new("sid", "", "cookie"),
  ]),
  Endpoint.new("/api/defaults", "POST", [
    Param.new("limit", "", "query"),
    Param.new("cursor", "", "query"),
    Param.new("email", "", "body"),
    Param.new("name", "", "body"),
  ]),
  Endpoint.new("/api/user/{id}", "GET", [Param.new("id", "", "path"), Param.new("expand", "", "query")]),
  Endpoint.new("/api/user/{id}", "PUT", [Param.new("id", "", "path"), Param.new("expand", "", "query"), Param.new("name", "", "body")]),
]

FunctionalTester.new("fixtures/javascript/nextjs_request_readers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Next.js destructured verb export line", tags: "functional" do
  it "points `export const { GET, POST } = handlers` at the export" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs_request_readers/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    auth = app.endpoints.select(&.url.starts_with?("/api/auth/"))
    auth.size.should eq(2)
    auth.each { |ep| ep.details.code_paths.first.line.should eq(5) }
  end
end
