require "../../func_spec.cr"

# Two HttpListener services under one scan base that answer the same route.
# `merge_endpoint` folds them into a single endpoint, and both services'
# params and both source files have to survive that fold.
expected_endpoints = [
  Endpoint.new("/health", "GET", [
    Param.new("X-Alpha", "", "header"),
    Param.new("X-Beta", "", "header"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/httplistener_multi_service/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "C# HttpListener analyzer across two services" do
  it "keeps a code path for every file that serves the route" do
    health = tester.app.endpoints.find { |e| e.url == "/health" && e.method == "GET" }
    health.should_not be_nil
    paths = health.as(Endpoint).details.code_paths.map(&.path)
    paths.any?(&.includes?("svcA/Program.cs")).should be_true
    paths.any?(&.includes?("svcB/Program.cs")).should be_true
  end
end
