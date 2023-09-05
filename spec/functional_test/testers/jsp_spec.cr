require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/get_param.jsp", "GET", [
    Param.new("username", "", "query"),
    Param.new("password", "", "query"),
  ]),
  Endpoint.new("/el.jsp", "GET", [Param.new("username", "", "query")]),
]

FunctionalTester.new("fixtures/jsp/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
