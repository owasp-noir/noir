require "../../func_spec.cr"

def drogon_endpoint_with_callees(url, method, params, callees)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  drogon_endpoint_with_callees("/ping", "GET", [Param.new("name", "", "query")], [
    Callee.new("req->getParameter", line: 39),
    Callee.new("HttpResponse::newHttpResponse", line: 40),
    Callee.new("callback", line: 41),
  ]),
  drogon_endpoint_with_callees("/items/{id}", "GET", [Param.new("id", "", "path")], [
    Callee.new("ItemService::load", line: 50),
    Callee.new("callback", line: 51),
    Callee.new("HttpResponse::newHttpJsonResponse", line: 51),
    Callee.new("renderItem", line: 51),
  ]),
  drogon_endpoint_with_callees("/items/{id}", "DELETE", [Param.new("id", "", "path")], [
    Callee.new("ItemService::load", line: 50),
    Callee.new("callback", line: 51),
    Callee.new("HttpResponse::newHttpJsonResponse", line: 51),
    Callee.new("renderItem", line: 51),
  ]),
  drogon_endpoint_with_callees("/api/users", "GET", [] of Param, [
    Callee.new("UserService::list", line: 21),
    Callee.new("HttpResponse::newHttpJsonResponse", line: 22),
    Callee.new("renderUsers", line: 22),
    Callee.new("callback", line: 23),
  ]),
  drogon_endpoint_with_callees("/api/users", "POST", [Param.new("body", "", "json")], [
    Callee.new("req->getJsonObject", line: 28),
    Callee.new("UserService::create", line: 29),
    Callee.new("callback", line: 30),
    Callee.new("makeCreatedResponse", line: 30),
  ]),
]

FunctionalTester.new("fixtures/cpp/drogon_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
