require "../../func_spec.cr"

def giraffe_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

profile_callees = [
  Callee.new("UserService.load", line: 19),
  Callee.new("AuditLog.write", line: 20),
  Callee.new("json", line: 23),
  Callee.new("serializeUser", line: 23),
]

pipeline_callees = [
  Callee.new("loadPipeline", line: 34),
  Callee.new("enrich", line: 34),
  Callee.new("renderPipeline", line: 34),
  Callee.new("json", line: 35),
]

expected_endpoints = [
  giraffe_endpoint_with_callees("/", "GET", [] of Param, [
    Callee.new("text", line: 12),
  ]),
  giraffe_endpoint_with_callees("/login", "POST", [] of Param, [
    Callee.new("handleLogin", line: 13),
  ]),
]

fallback_methods.each do |method|
  expected_endpoints << giraffe_endpoint_with_callees("/users/:int", method, [
    Param.new("int", "int", "path"),
  ], [
    Callee.new("handleUser", line: 14),
  ])
end

expected_endpoints << giraffe_endpoint_with_callees("/profile", "GET", [] of Param, profile_callees)
expected_endpoints << giraffe_endpoint_with_callees("/api/items", "PUT", [] of Param, [
  Callee.new("ItemController.update", line: 27),
])
expected_endpoints << giraffe_endpoint_with_callees("/pipeline", "PATCH", [] of Param, pipeline_callees)
# `route Urls.dashboard` inside a `GET >=> choose [...]` block: the path
# resolves from the `let dashboard = "/dashboard"` constant, the verb is
# inherited from the block, and the handler callee is still recovered.
expected_endpoints << giraffe_endpoint_with_callees("/dashboard", "GET", [] of Param, [
  Callee.new("AdminController.render", line: 46),
])

tester = FunctionalTester.new("fixtures/fsharp/giraffe_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Giraffe callees for multiline inline handlers" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/profile" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(profile_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "recovers the handler callee for a constant-path route" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/dashboard" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should eq(["AdminController.render"])
  end
end

it "does not leak sibling Giraffe route callees into routef handlers" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/users/:int" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq([
      {"handleUser", 14},
    ])
  end
end

it "populates Giraffe callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/profile" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/fsharp/giraffe_callees/Program.fs",
    ])
  end
end

it "does not stop multiline Giraffe handlers at inner list delimiters" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/pipeline" && found.method == "PATCH" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(pipeline_callees.map { |callee| {callee.name, callee.line} })
  end
end
