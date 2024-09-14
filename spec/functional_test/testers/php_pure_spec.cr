require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/get.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/header.php", "GET", [
    Param.new("X-API-KEY", "", "header"),
    Param.new("param1", "", "query"),
  ]),
  Endpoint.new("/post.php", "GET"),
  Endpoint.new("/post.php", "POST", [
    Param.new("param1", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/request.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/request.php", "POST", [Param.new("param1", "", "form")]),
]

FunctionalTester.new("fixtures/php_pure/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
