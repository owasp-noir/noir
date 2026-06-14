require "../../func_spec.cr"

def alfred_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

# `.all('/health', ...)` registers the handler against every verb.
health_callees = [Callee.new("healthCheck", line: 29)]
all_verbs = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

expected_endpoints = [
  # Inline lambda — callees from the body.
  alfred_endpoint("/users", "GET", [] of Param, [
    Callee.new("userService.findAll", line: 11),
    Callee.new("res.json", line: 12),
  ]),
  # Bare function reference handler — recorded as the single callee.
  alfred_endpoint("/users", "POST", [] of Param, [Callee.new("createUser", line: 16)]),
  # Typed path param `:id:int` collapses to `{id}`.
  alfred_endpoint("/users/{id}", "GET", [Param.new("id", "", "path")], [
    Callee.new("getUser", line: 20),
  ]),
  # `delete` with a trailing `middleware:` argument after the handler:
  # the lambda body (not the middleware) is what gets scanned.
  alfred_endpoint("/users/{id}", "DELETE", [Param.new("id", "", "path")], [
    Callee.new("deleteUser", line: 25),
  ]),
  # Routes registered from another file via an `Alfred`-typed parameter.
  alfred_endpoint("/auth/login", "POST", [] of Param, [Callee.new("authService.login", line: 8)]),
  alfred_endpoint("/auth/profile", "GET", [] of Param, [Callee.new("getProfile", line: 11)]),
  # Nested routes: `app.route('/admin/')..get('', dashboard)..post('users', ...)`.
  # The base path composes with each cascade sub-path.
  alfred_endpoint("/admin/", "GET", [] of Param, [Callee.new("dashboard", line: 15)]),
  alfred_endpoint("/admin/users", "POST", [] of Param, [Callee.new("createAdminUser", line: 16)]),
  alfred_endpoint("/admin/users/{id}", "DELETE", [Param.new("id", "", "path")], [
    Callee.new("deleteAdminUser", line: 17),
  ]),
]

all_verbs.each do |verb|
  expected_endpoints << alfred_endpoint("/health", verb, [] of Param, health_callees)
  # `..all('*', ...)` catch-all on the `/admin/` nested route.
  expected_endpoints << alfred_endpoint("/admin/*", verb, [] of Param)
end

tester = FunctionalTester.new("fixtures/dart/alfred/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "extracts callees from an Alfred lambda handler body" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/users" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq([
      {"userService.findAll", 11},
      {"res.json", 12},
    ])
  end
end

it "skips the handler's trailing middleware argument when scanning callees" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/users/{id}" && found.method == "DELETE" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should eq(["deleteUser"])
  end
end

it "composes Alfred nested route() base paths with cascade sub-paths" do
  urls = tester.app.endpoints.map(&.url).to_set
  urls.should contain("/admin/")
  urls.should contain("/admin/users")
  urls.should contain("/admin/users/{id}")
end
