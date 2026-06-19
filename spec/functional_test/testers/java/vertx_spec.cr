require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/status", "HEAD"),
  Endpoint.new("/api/options", "OPTIONS"),
  Endpoint.new("/api/products/:category", "GET", [Param.new("category", "", "path")]),
  Endpoint.new("/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/orders", "POST"),
  Endpoint.new("/orders/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/imports/:importId", "POST", [Param.new("importId", "", "path")]),
  Endpoint.new("/api/reports/:reportId", "GET", [Param.new("reportId", "", "path")]),
  Endpoint.new("/api/exports/:exportId", "GET", [Param.new("exportId", "", "path")]),
  Endpoint.new("/api/imports/:importId", "DELETE", [Param.new("importId", "", "path")]),
  Endpoint.new("/api/tasks/:taskId", "GET", [Param.new("taskId", "", "path")]),
  Endpoint.new("/jobs/:jobId", "POST", [Param.new("jobId", "", "path")]),
  Endpoint.new("/api/any/:anyId", "ANY", [Param.new("anyId", "", "path")]),
  Endpoint.new("/eventbus/*", "ANY"),
  Endpoint.new("/static/*", "GET"),
  Endpoint.new("/api/v1/items", "GET"),
  Endpoint.new("/api/v1/items", "POST"),
  Endpoint.new("/admin/metrics/:metricId", "GET", [Param.new("metricId", "", "path")]),
]

FunctionalTester.new("fixtures/java/vertx/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
