require "../../func_spec.cr"

# `axum::routing::any(...)` and service mounts (`route_service`,
# `nest_service`, `fallback_service`) register a route under every
# HTTP method. noir now fans them out so SARIF / Postman / OpenAPI
# consumers see real HTTP methods instead of a non-HTTP "ANY"
# string. The four routes below (/ws, /favicon.ico, /assets/*, /*)
# each surface as one endpoint per canonical method.
ANY_FAN_OUT = %w[GET POST PUT PATCH DELETE HEAD OPTIONS]

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/foo", "GET"),
  Endpoint.new("/bar", "POST"),
  Endpoint.new("/search", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("form", "", "form"),
  ]),
  Endpoint.new("/headers", "GET", [
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/session", "GET", [
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/admin", "POST"),
  Endpoint.new("/internal/health", "GET"),
  Endpoint.new("/v1/projects", "GET"),
  Endpoint.new("/v1/projects/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/root/api/audit", "GET"),
]
%w[/ws /favicon.ico /assets/* /*].each do |path|
  ANY_FAN_OUT.each { |verb| expected_endpoints << Endpoint.new(path, verb) }
end

FunctionalTester.new("fixtures/rust/axum/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
