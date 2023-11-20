require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/api/me", "GET", [
    Param.new("q", "", "query"),
    Param.new("query", "", "query"),
    Param.new("filter", "", "query"),
    Param.new("X-Forwarded-For", "", "header"),
  ]),
  Endpoint.new("/api/sign_ins", "POST", [Param.new("users", "", "json")]),
  Endpoint.new("/api/sign_ups", "POST"),
]

FunctionalTester.new("fixtures/crystal_lucky/", {
  :techs     => 1,
  :endpoints => 5,
}, extected_endpoints).test_all
