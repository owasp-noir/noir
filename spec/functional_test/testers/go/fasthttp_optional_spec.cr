require "../../func_spec.cr"

# Regression test: fasthttp/router path-parameter dialects must normalize
# to the canonical `{name}` placeholder. The optional marker (`{name?}`)
# and the optional+regex form (`{slug?:[a-z]+}`) previously leaked the `?`
# into the param name and kept the regex body in the URL.
#
# Coverage:
#   - GET /optional/{name}  — `{name?}`        optional
#   - GET /regex/{id}       — `{id:[0-9]+}`    inline regex
#   - GET /combo/{slug}     — `{slug?:[a-z]+}` optional + regex
expected_endpoints = [
  Endpoint.new("/optional/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/regex/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/combo/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/go/fasthttp_optional/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
