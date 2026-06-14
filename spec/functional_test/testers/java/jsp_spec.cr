require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/get_param.jsp", "GET", [
    Param.new("username", "", "query"),
    Param.new("password", "", "query"),
  ]),
  Endpoint.new("/el.jsp", "GET", [Param.new("username", "", "query")]),
  # A JSP under `src/main/webapp/` is served relative to that root — the
  # build prefix is stripped (`/reports/summary.jsp`, not the repo path).
  Endpoint.new("/reports/summary.jsp", "GET", [Param.new("range", "", "query")]),
  Endpoint.new("/attribute.jsp", "GET", [Param.new("userId", "", "query")]),
  Endpoint.new("/header.jsp", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/cookie.jsp", "GET", [Param.new("", "", "cookie")]),
  Endpoint.new("/advanced.jsp", "GET", [
    Param.new("q", "", "query"),
    Param.new("tag", "", "query"),
    Param.new("mode", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("category", "", "query"),
    Param.new("X-Trace", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("csrf", "", "form"),
  ]),
  Endpoint.new("/reports/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/reports/*", "GET", [
    Param.new("reportId", "", "query"),
    Param.new("X-Report-Token", "", "header"),
  ]),
  Endpoint.new("/api/reports", "GET", [
    Param.new("reportId", "", "query"),
    Param.new("X-Report-Token", "", "header"),
  ]),
  Endpoint.new("/reports/*", "POST", [
    Param.new("title", "", "form"),
  ]),
  Endpoint.new("/api/reports", "POST", [
    Param.new("title", "", "form"),
  ]),
  Endpoint.new("/legacy/submit", "POST", [
    Param.new("legacyId", "", "form"),
  ]),
  Endpoint.new("/audit", "GET", [
    Param.new("auditId", "", "query"),
    Param.new("X-Audit-Token", "", "header"),
  ]),
  Endpoint.new("/audit", "POST", [
    Param.new("note", "", "form"),
    Param.new("", "", "cookie"),
  ]),
  Endpoint.new("/admin", "GET"),
]

FunctionalTester.new("fixtures/java/jsp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
