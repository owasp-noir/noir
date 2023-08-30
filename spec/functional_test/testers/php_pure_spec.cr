require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/get.php", "GET"),
  Endpoint.new("/header.php", "GET", [Param.new("X-API-KEY", "", "header")]),
  Endpoint.new("/post.php", "GET"),
  Endpoint.new("/post.php", "POST", [Param.new("param1", "", "body")]),
  Endpoint.new("/request.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/request.php", "POST", [Param.new("param1", "", "body")]),
]

FunctionalTester.new("fixtures/php_pure/", {
  :techs     => 1,
  :endpoints => 6,
}, extected_endpoints).test_all
