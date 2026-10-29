require "../../func_spec.cr"

# #3266: `basePath` in `next.config.js` prefixes every route, pages router
# and app router alike.
expected_endpoints = [
  Endpoint.new("/shop/api/items", "GET"),
] of Endpoint
%w[GET POST PUT DELETE PATCH].each do |method|
  expected_endpoints << Endpoint.new("/shop/api/search", method, [Param.new("q", "", "query")])
end

FunctionalTester.new("fixtures/javascript/nextjs_base_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
