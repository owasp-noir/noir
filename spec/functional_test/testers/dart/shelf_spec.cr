require "../../func_spec.cr"

expected_endpoints = [
  # Cascade-style registrations on the root router.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),

  # `..all('/echo', ...)` fans out to every standard verb.
  Endpoint.new("/echo", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/echo", "PUT"),
  Endpoint.new("/echo", "PATCH"),
  Endpoint.new("/echo", "DELETE"),
  Endpoint.new("/echo", "HEAD"),
  Endpoint.new("/echo", "OPTIONS"),

  # `apiRouter` is mounted at `/api/v1/` on the root router. The
  # regex constraint inside `<itemId|[0-9]+>` is stripped from the
  # surfaced path param.
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  # Direct `apiRouter.patch(...)` outside the cascade.
  Endpoint.new("/api/v1/items/{itemId}", "PATCH", [Param.new("itemId", "", "path")]),

  # `WidgetsController` builds a `Router()` inside a getter and is mounted
  # at `/widgets/`. The routes must inherit the mount prefix even though
  # the inner local variable is `r`, not the class name.
  Endpoint.new("/widgets/list", "GET"),
  Endpoint.new("/widgets/{id}", "GET", [Param.new("id", "", "path")]),

  # `TasksController` uses the `@Route.<verb>('/path')` code-gen style and
  # is mounted at `/tasks/`.
  Endpoint.new("/tasks/all", "GET"),
  Endpoint.new("/tasks/{id}/done", "POST", [Param.new("id", "", "path")]),

  # (`test/server_test.dart` builds a `Router()` too, but lives under
  # `test/` and must be ignored.)
]

FunctionalTester.new("fixtures/dart/shelf/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# Callee/AI-context coverage: a bare function-reference handler is
# recorded as a callee, and `@Route`-annotated handler bodies are
# scanned for their callees.
callee_tester = FunctionalTester.new("fixtures/dart/shelf/", {} of Symbol => Int32, [] of Endpoint, {
  "include_callee" => YAML::Any.new(true),
})
callee_tester.perform_tests

it "records bare function-reference handlers as callees" do
  endpoint = callee_tester.app.endpoints.find { |found| found.url == "/users" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should contain("_listUsers")
  end
end

it "extracts callees from @Route-annotated handler bodies" do
  endpoint = callee_tester.app.endpoints.find { |found| found.url == "/tasks/{id}/done" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should contain("_repository.complete")
  end
end
