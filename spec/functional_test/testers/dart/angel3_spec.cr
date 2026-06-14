require "../../func_spec.cr"

def angel3_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

health_callees = [Callee.new("healthCheck", line: 26)]
all_verbs = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

expected_endpoints = [
  angel3_endpoint("/users", "GET", [] of Param, [
    Callee.new("userService.findAll", line: 12),
    Callee.new("res.json", line: 13),
  ]),
  angel3_endpoint("/users", "POST", [] of Param, [Callee.new("createUser", line: 17)]),
  angel3_endpoint("/users/{id}", "GET", [Param.new("id", "", "path")], [Callee.new("getUser", line: 20)]),
  # Optional capture `:slug?` drops the trailing `?`.
  angel3_endpoint("/posts/{slug}", "GET", [Param.new("slug", "", "path")], [Callee.new("getPost", line: 23)]),
  # Nested `group` blocks compose their prefixes; the `chain([...])`
  # middleware before the group does not affect the URL.
  angel3_endpoint("/api/version", "GET"),
  angel3_endpoint("/api/v2/widgets", "POST", [] of Param, [Callee.new("createWidget", line: 34)]),
  # Registered via an `Angel`-typed parameter in another file.
  angel3_endpoint("/status", "GET", [] of Param, [Callee.new("statusService.check", line: 6)]),
]

all_verbs.each do |verb|
  expected_endpoints << angel3_endpoint("/health", verb, [] of Param, health_callees)
end

tester = FunctionalTester.new("fixtures/dart/angel3/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "composes nested Angel3 group() prefixes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/api/v2/widgets" && found.method == "POST" }
  endpoint.should_not be_nil
end

it "does not treat a package:http client get() as a route" do
  tester.app.endpoints.any?(&.url.includes?("example.com")).should be_false
end
