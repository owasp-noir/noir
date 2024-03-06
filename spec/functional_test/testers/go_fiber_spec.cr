require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/info", "GET", [
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/update", "POST", [
    Param.new("name", "", "form"),
    Param.new("auth", "", "cookie"),
    Param.new("X-API-Key", "", "header"),
    Param.new("Vary", "Origin", "header"),
  ]),
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/ws", "GET"),
  Endpoint.new("/admin/users", "GET"),
]

FunctionalTester.new("fixtures/go_fiber/", {
  :techs     => 1,
  :endpoints => 5,
}, extected_endpoints).test_all
