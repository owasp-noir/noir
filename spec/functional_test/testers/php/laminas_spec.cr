require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/admin/users", "POST"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/application/{action}", "GET", [Param.new("action", "", "path")]),
  Endpoint.new("/locale/{locale}-{slug}", "GET", [
    Param.new("locale", "", "path"),
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/download/{id}.{format}", "GET", [
    Param.new("id", "", "path"),
    Param.new("format", "", "path"),
  ]),
  Endpoint.new("/blog/rss", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/reports/{reportId}", "GET", [Param.new("reportId", "", "path")]),
  Endpoint.new("/api/reports/{reportId}", "PATCH", [Param.new("reportId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "GET", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "POST", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "PUT", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "PATCH", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "DELETE", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "OPTIONS", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/audit/{auditId}", "HEAD", [Param.new("auditId", "", "path")]),
  Endpoint.new("/api/broadcast", "GET"),
  Endpoint.new("/api/broadcast", "POST"),
  Endpoint.new("/api/broadcast", "PUT"),
  Endpoint.new("/api/broadcast", "PATCH"),
  Endpoint.new("/api/broadcast", "DELETE"),
  Endpoint.new("/api/broadcast", "OPTIONS"),
  Endpoint.new("/api/broadcast", "HEAD"),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("force", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/php/laminas/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
