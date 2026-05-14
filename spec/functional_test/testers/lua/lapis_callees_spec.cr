require "../../func_spec.cr"

def lapis_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

users_callees = [
  Callee.new("UserService.list", line: 10),
  Callee.new("Audit.write", line: 11),
  Callee.new("render_json", line: 12),
]

update_callees = [
  Callee.new("Users.update", line: 16),
  Callee.new("respond", line: 17),
]

health_callees = [
  Callee.new("health_check", line: 21),
  Callee.new("respond_ok", line: 22),
]

named_callees = [
  Callee.new("Profiles.find", line: 5),
  Callee.new("render_json", line: 6),
]

noise_callees = [
  Callee.new("clean_text", line: 30),
]

identifier_callees = [
  Callee.new("IdentifierService.show", line: 34),
]

dashboard_callees = [
  Callee.new("AdminService.stats", line: 7),
  Callee.new("render_admin", line: 8),
]

admin_user_callees = [
  Callee.new("AdminUsers.find", line: 12),
  Callee.new("json_response", line: 13),
]

moon_callees = [
  Callee.new("moon_service.load", line: 5),
  Callee.new("render_moon", line: 6),
]

moon_user_callees = [
  Callee.new("Users.find", line: 8),
  Callee.new("json_response", line: 9),
]

expected_endpoints = [
  lapis_endpoint_with_callees("/users", "GET", [] of Param, users_callees),
  lapis_endpoint_with_callees("/users/:id", "POST", [
    Param.new("id", "", "path"),
  ], update_callees),
  lapis_endpoint_with_callees("/named", "GET", [] of Param, named_callees),
  lapis_endpoint_with_callees("/string-noise", "GET", [] of Param, noise_callees),
  lapis_endpoint_with_callees("/identifier", "GET", [] of Param, identifier_callees),
]

fallback_methods.each do |method|
  expected_endpoints << lapis_endpoint_with_callees("/health", method, [] of Param, health_callees)
  expected_endpoints << lapis_endpoint_with_callees("/admin/dashboard", method, [] of Param, dashboard_callees)
  expected_endpoints << lapis_endpoint_with_callees("/admin/users/:id", method, [
    Param.new("id", "", "path"),
  ], admin_user_callees)
  expected_endpoints << lapis_endpoint_with_callees("/moon", method, [] of Param, moon_callees)
  expected_endpoints << lapis_endpoint_with_callees("/moon/users/:id", method, [
    Param.new("id", "", "path"),
  ], moon_user_callees)
end

tester = FunctionalTester.new("fixtures/lua/lapis_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Lapis callees for inline Lua handlers" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/users" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(users_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "reuses same Lapis callees for app:match fallback methods" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/health" && found.method == "PATCH" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(health_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "resolves same-file string action handlers for Lapis table routes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/admin/dashboard" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(dashboard_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "extracts MoonScript action callees without leaking adjacent routes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/moon/users/:id" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(moon_user_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "ignores fake calls in Lua strings and comments" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/string-noise" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(noise_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "resolves identifier handler variables for Lapis routes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/identifier" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(identifier_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "populates Lapis callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/named" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/lua/lapis_callees/app.lua",
    ])
  end
end
