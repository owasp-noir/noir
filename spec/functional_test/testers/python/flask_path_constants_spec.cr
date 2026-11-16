require "../../func_spec.cr"

# A route path or `url_prefix` spelled as a module constant, a `+`
# concatenation, adjacent literals or an f-string naming a module constant
# is the string it evaluates to. The route on a bare constant used to be
# dropped, and the f-string kept `{REPORTS}` as a path parameter. A name the
# module binds twice (`MODE`) is not guessed, and an f-string field that is
# no module string (`{tenant}`) stays a placeholder.
expected_endpoints = [
  Endpoint.new("/api/files/download/<path:filename>", "GET", [Param.new("filename", "", "path")]),
  Endpoint.new("/api/reports/<int:year>", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/hooks/github", "POST"),
  Endpoint.new("/api/tenants/{tenant}", "GET", [Param.new("tenant", "", "path")]),
]

FunctionalTester.new("fixtures/python/flask_path_constants/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
