require "../../func_spec.cr"

# finale-rest / epilogue `resource({ endpoints: [plural, singular] })`
# registers list + create on the plural path and read + update + delete on
# the singular one. The juice-shop shape (a template over a destructured
# for-of over a same-file array literal) expands per entry; the guard-only
# `app.put('/api/Hints/:id', …)` merges into the generated row. A
# commented-out call and an unresolvable `${prefix}` emit nothing.

expected_endpoints = [] of Endpoint
{"/api/Users", "/api/Hints"}.each do |base|
  expected_endpoints << Endpoint.new(base, "GET")
  expected_endpoints << Endpoint.new(base, "POST")
  {"GET", "PUT", "DELETE"}.each do |method|
    expected_endpoints << Endpoint.new("#{base}/:id", method, [Param.new("id", "", "path")])
  end
end
expected_endpoints << Endpoint.new("/tags", "GET")
expected_endpoints << Endpoint.new("/tags", "POST")
{"GET", "PUT", "DELETE"}.each do |method|
  expected_endpoints << Endpoint.new("/tags/:tagId", method, [Param.new("tagId", "", "path")])
end

FunctionalTester.new("fixtures/javascript/express_finale/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
