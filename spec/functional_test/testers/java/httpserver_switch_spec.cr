require "../../func_spec.cr"

# Switch-based method dispatch in JDK HttpServer handlers.
#   /actions — colon-form `switch (method)` yields GET + POST; an unrelated
#              `switch (op)` on a header value must NOT leak its DELETE/PUT
#              case labels as HTTP verbs (case-label scan is scoped to the
#              method switch block).
#   /feed    — arrow-form `case "X" ->` (Java 14+) on a chained selector
#              `getRequestMethod().toUpperCase()` yields GET + HEAD.
expected_endpoints = [
  Endpoint.new("/actions", "GET", [
    Param.new("X-Op", "", "header"),
  ]),
  Endpoint.new("/actions", "POST", [
    Param.new("X-Op", "", "header"),
  ]),
  Endpoint.new("/feed", "GET"),
  Endpoint.new("/feed", "HEAD"),
]

tester = FunctionalTester.new("fixtures/java/httpserver_switch/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not leak unrelated switch case labels as HTTP verbs" do
  tester.app.endpoints.any? { |e| e.url == "/actions" && (e.method == "DELETE" || e.method == "PUT") }.should be_false
end
