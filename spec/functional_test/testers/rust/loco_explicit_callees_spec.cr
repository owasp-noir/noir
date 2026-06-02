require "../../func_spec.cr"

# Callee/ai-context wiring for the explicit `Routes::new().add(...)`
# path: handlers are looked up by name in the file's function index, so
# their bodies' calls surface as callees even though the route is
# registered separately from the `async fn` definition.
index = Endpoint.new("/api/posts", "GET", [Param.new("query", "", "query")]).tap do |ep|
  ep.push_callee(Callee.new("PostService::list", line: 32))
  ep.push_callee(Callee.new("PostPresenter::render", line: 33))
  ep.push_callee(Callee.new("format::json", line: 34))
end

create = Endpoint.new("/api/posts", "POST", [Param.new("body", "", "json")]).tap do |ep|
  ep.push_callee(Callee.new("PostService::create", line: 38))
  ep.push_callee(Callee.new("AuditLog::write", line: 39))
  ep.push_callee(Callee.new("format::json", line: 40))
end

expected_endpoints = [
  index,
  create,
]

FunctionalTester.new("fixtures/rust/loco/", {
  :techs => 2,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
