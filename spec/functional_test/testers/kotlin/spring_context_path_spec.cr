require "../../func_spec.cr"

user_endpoint = Endpoint.new("/api/users/{id}", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("profileService.find", line: 16))
end

graphql_endpoint = Endpoint.new("/api/graphql#Query.profile", "POST", [
  Param.new("id", "", "json"),
  Param.new("graphql_query_profile", "query($id: String) { profile(id: $id) }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("profileService.find", line: 24))
end

expected_endpoints = [
  user_endpoint,
  graphql_endpoint,
]

FunctionalTester.new("fixtures/kotlin/spring_context_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
