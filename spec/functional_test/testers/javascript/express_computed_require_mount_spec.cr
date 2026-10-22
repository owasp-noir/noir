require "../../func_spec.cr"

# A router bound through a computed `require()` specifier
# (`__dirname + '/x'`, `` `${__dirname}/x` ``, `path.join(__dirname, ...)`,
# `path.resolve(__dirname, ...)`) keeps its `app.use` mount prefix.
expected_endpoints = [
  Endpoint.new("/api/pets/all", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/owners/all", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/vets/all", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/toys/all", "GET", [Param.new("limit", "", "query")]),
]

FunctionalTester.new("fixtures/javascript/express_computed_require_mount/", {
  :techs => 1,
}, expected_endpoints).perform_tests
