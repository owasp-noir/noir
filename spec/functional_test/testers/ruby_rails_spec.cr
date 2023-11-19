require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/1", "GET"),
  Endpoint.new("/posts", "POST", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
]

FunctionalTester.new("fixtures/ruby_rails/", {
  :techs     => 1,
  :endpoints => 6,
}, extected_endpoints).test_all
