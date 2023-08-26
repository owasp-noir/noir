require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/test.html", "GET"),
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/1", "GET"),
  Endpoint.new("/posts", "POST", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
]

FunctionalTester.new("fixtures/rails/", {
  :techs     => 1,
  :endpoints => 5,
}, extected_endpoints).test_all
