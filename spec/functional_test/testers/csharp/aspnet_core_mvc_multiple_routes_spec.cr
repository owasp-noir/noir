require "../../func_spec.cr"

# Every `[Route]` on an action is a selector of its own, and so is a verb
# attribute with a template; a template-less verb joins each `[Route]`.
# `[Route("")]` on a controller without a route is the site root.
expected_endpoints = [
  Endpoint.new("/", "ANY", [Param.new("id", "", "query")]),
  Endpoint.new("/Home", "ANY", [Param.new("id", "", "query")]),
  Endpoint.new("/Home/Index", "ANY", [Param.new("id", "", "query")]),
  Endpoint.new("/Home/Index/{id}", "ANY", [Param.new("id", "", "path")]),
  Endpoint.new("/Home/About", "ANY", [Param.new("id", "", "query")]),
  Endpoint.new("/Home/About/{id}", "ANY", [Param.new("id", "", "path")]),
  Endpoint.new("/api/reports/latest", "GET"),
  Endpoint.new("/api/reports/current", "GET"),
  Endpoint.new("/api/reports/archive", "ANY"),
  Endpoint.new("/api/reports/history", "GET"),
  Endpoint.new("/api/reports/run", "POST"),
  Endpoint.new("/api/reports/execute", "POST"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_multiple_routes/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
