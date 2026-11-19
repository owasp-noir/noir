require "../../func_spec.cr"

# `parameter(s)` with typed, optional and defaulted arguments, two
# directives in one route, and `cookie` / `optionalCookie`. A default value
# (`withDefault("white")`) and a `setCookie` are not inputs.
q = ->(names : Array(String)) { names.map { |name| Param.new(name, "", "query") } }

expected_endpoints = [
  Endpoint.new("/p1-defaults", "GET", q.call(%w[color backgroundColor count debug])),
  Endpoint.new("/p2-single-typed", "GET", q.call(%w[count])),
  Endpoint.new("/p3-single-optional", "GET", q.call(%w[cursor])),
  Endpoint.new("/p4-two-directives", "GET", q.call(%w[a b c d])),
  Endpoint.new("/p5-cookie", "GET", [Param.new("session", "", "cookie"), Param.new("theme", "", "cookie")]),
  Endpoint.new("/p6-control", "GET", q.call(%w[x y])),
]

FunctionalTester.new("fixtures/scala/akka_parameter_forms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
