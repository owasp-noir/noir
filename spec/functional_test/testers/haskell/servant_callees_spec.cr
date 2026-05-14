require "../../func_spec.cr"

def servant_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

list_users_callees = [
  Callee.new("loadUsers", line: 35),
  Callee.new("audit", line: 36),
]

get_user_callees = [
  Callee.new("UserRepo.find", line: 41),
  Callee.new("throwError", line: 44),
]

health_callees = [
  Callee.new("healthCheck", line: 48),
]

expected_endpoints = [
  servant_endpoint_with_callees("/v1/users", "GET", [] of Param, list_users_callees),
  servant_endpoint_with_callees("/v1/users/:userId", "GET", [
    Param.new("userId", "Integer", "path"),
  ], get_user_callees),
  servant_endpoint_with_callees("/health", "GET", [] of Param, health_callees),
]

tester = FunctionalTester.new("fixtures/haskell/servant_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Servant callees by flattened server order" do
  list_endpoint = tester.app.endpoints.find { |found| found.url == "/v1/users" && found.method == "GET" }
  list_endpoint.should_not be_nil
  list_endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(list_users_callees.map { |callee| {callee.name, callee.line} })
  end

  endpoint = tester.app.endpoints.find { |found| found.url == "/v1/users/:userId" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(get_user_callees.map { |callee| {callee.name, callee.line} })
  end

  health_endpoint = tester.app.endpoints.find { |found| found.url == "/health" && found.method == "GET" }
  health_endpoint.should_not be_nil
  health_endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(health_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "populates Servant callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/health" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/haskell/servant_callees/src/Api.hs",
    ])
  end
end

mismatch_expected = [
  Endpoint.new("/one", "GET"),
  Endpoint.new("/two", "GET"),
]

mismatch_tester = FunctionalTester.new("fixtures/haskell/servant_callees_mismatch/", {
  :techs     => 1,
  :endpoints => mismatch_expected.size,
}, mismatch_expected, {
  "include_callee" => YAML::Any.new(true),
})
mismatch_tester.perform_tests

it "leaves Servant callees empty when server leaf count mismatches endpoint count" do
  mismatch_tester.app.endpoints.each do |endpoint|
    endpoint.callees.should be_empty
  end
end

multi_api_public = Endpoint.new("/public", "GET")
multi_api_public.push_callee(Callee.new("loadPublic", line: 19))

multi_api_expected = [
  multi_api_public,
  Endpoint.new("/admin", "GET"),
]

multi_api_tester = FunctionalTester.new("fixtures/haskell/servant_callees_multi_api/", {
  :techs     => 1,
  :endpoints => multi_api_expected.size,
}, multi_api_expected, {
  "include_callee" => YAML::Any.new(true),
})
multi_api_tester.perform_tests

it "does not reuse a same-file generic Servant server for a different API alias" do
  admin = multi_api_tester.app.endpoints.find { |found| found.url == "/admin" && found.method == "GET" }
  admin.should_not be_nil
  admin.try do |endpoint|
    endpoint.callees.should be_empty
  end
end

cross_alias_expected = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/health", "GET"),
]

cross_alias_tester = FunctionalTester.new("fixtures/haskell/servant_callees_cross_alias/", {
  :techs     => 1,
  :endpoints => cross_alias_expected.size,
}, cross_alias_expected, {
  "include_callee" => YAML::Any.new(true),
})
cross_alias_tester.perform_tests

it "does not expand nested Servant server aliases from another file" do
  cross_alias_tester.app.endpoints.each do |endpoint|
    endpoint.callees.should be_empty
  end
end
