require "../../func_spec.cr"

# Quarkus written in Kotlin (#2856). `GreetingResource.kt` opens with a
# bare `@ApplicationScoped` straight after the imports, which is the
# shape tree-sitter-kotlin splits off the class into a sibling node, so
# the `/hello` prefix only survives if the stray annotations are read.
# Reactive routes (`@Route`) parse Kotlin's `name: Type` parameters.
expected_endpoints = [
  Endpoint.new("/svc/hello", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Lang", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("service.greet", line: 18))
  end,
  Endpoint.new("/svc/hello/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/svc/hello", "POST", [
    Param.new("message", "", "json"),
    Param.new("lang", "en", "json"),
  ]),
  Endpoint.new("/svc/ping", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/svc/create-item", "POST", [Param.new("item", "", "json")]).tap do |ep|
    ep.push_callee(Callee.new("audit.record", line: 16))
  end,
]

FunctionalTester.new("fixtures/java/quarkus_kotlin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
