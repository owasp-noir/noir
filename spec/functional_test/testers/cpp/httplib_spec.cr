require "../../func_spec.cr"

def httplib_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  # Inline lambda: query + header params, callees from the body.
  httplib_endpoint("/", "GET", [
    Param.new("q", "", "query"),
    Param.new("Authorization", "", "header"),
  ], [
    Callee.new("req.get_param_value"),
    Callee.new("req.get_header_value"),
  ]),
  # `:id` named path parameter → {id}.
  httplib_endpoint("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  # POST body read in the lambda.
  httplib_endpoint("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Named-function handler resolved from the same file: path id + its own
  # header read, plus the repository callee.
  httplib_endpoint("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
  ], [
    Callee.new("repository_delete"),
  ]),
  # Raw-string regex route, kept verbatim.
  httplib_endpoint("/files/(.*)", "GET"),
  # Plain route, no params.
  httplib_endpoint("/settings", "PATCH"),
]

tester = FunctionalTester.new("fixtures/cpp/httplib/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "cpp-httplib route discovery edge cases" do
  it "does not treat a Client verb call as a route" do
    tester.app.endpoints.any? { |e| e.url == "/external" }.should be_false
  end

  it "normalizes `:id` named params but keeps regex routes verbatim" do
    tester.app.endpoints.any? { |e| e.url == "/users/:id" }.should be_false
    tester.app.endpoints.any? { |e| e.url == "/files/(.*)" }.should be_true
  end
end
