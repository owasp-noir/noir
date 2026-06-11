require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/items", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/items", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/items/<int:item_id>", "DELETE"),
  Endpoint.new("/api/v1/users", "POST", [Param.new("username", "", "json")]),
  Endpoint.new("/mounted/child/reports/<int:report_id>", "GET", [
    Param.new("mode", "", "query"),
  ]),
  Endpoint.new("/reports/<int:report_id>", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/reports", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/dispatch-reports", "GET", [Param.new("owner", "", "query")]),
  Endpoint.new("/dispatch-reports", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/v1/registered-search", "GET", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/api/v1/registered-create", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/api/v1/external-search", "GET", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/sync-update", "POST", [Param.new("page", "", "query"), Param.new("name", "", "json")]),
  Endpoint.new("/ws", "GET"),
]

FunctionalTester.new("fixtures/python/quart/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
