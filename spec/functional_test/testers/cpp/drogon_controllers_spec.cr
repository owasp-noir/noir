require "../../func_spec.cr"

def drogon_ctrl_endpoint(url, method, protocol = "http", params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  endpoint.protocol = protocol
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  # METHOD_ADD with an empty pattern → bare controller path prefix.
  drogon_ctrl_endpoint("/app/v2/ApiCtrl", "GET", "http", [] of Param, [
    Callee.new("HttpResponse::newHttpResponse"),
    Callee.new("callback"),
  ]),
  # Multi-line METHOD_ADD with a path param; handler reads a query param.
  drogon_ctrl_endpoint("/app/v2/ApiCtrl/show/{id}", "GET", "http", [
    Param.new("id", "", "path"),
    Param.new("q", "", "query"),
  ], [
    Callee.new("UserService::find"),
    Callee.new("renderUser"),
  ]),
  # ADD_METHOD_TO → absolute path, two methods.
  drogon_ctrl_endpoint("/ping", "GET"),
  drogon_ctrl_endpoint("/ping", "POST"),
  # ADD_METHOD_VIA_REGEX → absolute regex path.
  drogon_ctrl_endpoint("/legacy/(.*)", "GET"),
  # WS_PATH_ADD → websocket endpoint.
  drogon_ctrl_endpoint("/chat", "GET", "ws"),
  # Multi-line registerHandler whose query-string constraint becomes a param.
  drogon_ctrl_endpoint("/search", "GET", "http", [
    Param.new("q", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/cpp/drogon_controllers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "Drogon controller routing edge cases" do
  it "ignores macros inside block comments" do
    tester.app.endpoints.any? { |e| e.url == "/ghost" }.should be_false
  end

  it "strips the query string from the registered path" do
    tester.app.endpoints.any? { |e| e.url.includes?("?") }.should be_false
  end
end
