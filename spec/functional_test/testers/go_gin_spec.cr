require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/public/secret.html", "GET"),
]

FunctionalTester.new("fixtures/go_gin/", {
  :techs     => 1,
  :endpoints => 3,
}, extected_endpoints).test_all
