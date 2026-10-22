require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/orders/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  Endpoint.new("/orders", "POST", [
    Param.new("order", "", "json"),
  ]),
  Endpoint.new("/orders/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("order", "", "json"),
  ]),
  Endpoint.new("/orders/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/Ping", "POST", [
    Param.new("payload", "", "json"),
  ]),
  Endpoint.new("/Search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/files/{path}", "GET", [
    Param.new("path", "", "path"),
  ]),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/status/{component}", "PATCH", [
    Param.new("component", "", "path"),
    Param.new("s", "", "json"),
  ]),
  Endpoint.new("/Fetch", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/Latest", "GET"),
  Endpoint.new("/pages/{page}", "GET", [
    Param.new("page", "", "path"),
  ]),
] + WILDCARD_HTTP_METHODS.map do |verb|
  Endpoint.new("/echo", verb, verb == "GET" ? [Param.new("body", "", "query")] : [Param.new("body", "", "json")])
end

tester = FunctionalTester.new("fixtures/csharp/wcf/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests
