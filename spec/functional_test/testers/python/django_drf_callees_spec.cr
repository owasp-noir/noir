require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/articles/", "GET", [
    Param.new("status", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.query_params.get", line: 32))
    ep.push_callee(Callee.new("HttpResponse", line: 33))
  end,

  Endpoint.new("/api/articles/{article_id}/publish/", "POST", [
    Param.new("reason", "", "form"),
    Param.new("article_id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.data.get", line: 41))
    ep.push_callee(Callee.new("HttpResponse", line: 42))
  end,
]

tester = FunctionalTester.new("fixtures/python/django/", {
  :techs => 1,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests
