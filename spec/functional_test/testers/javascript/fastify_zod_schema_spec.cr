require "../../func_spec.cr"

# Route `schema` given as zod (`fastify-type-provider-zod`) or imported
# from another module.
expected_endpoints = [
  Endpoint.new("/s00-same-file", "POST", [Param.new("localSku", "", "json")]),
  Endpoint.new("/s01-imported-parts", "POST", [
    Param.new("sku", "", "json"), Param.new("qty", "", "json"), Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/s02-imported-whole", "POST", [
    Param.new("sku", "", "json"), Param.new("qty", "", "json"), Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/s03-zod-shorthand", "POST", [
    Param.new("zname", "", "json"), Param.new("zage", "", "json"), Param.new("zq", "", "query"),
  ]),
  Endpoint.new("/s04-zod-route", "POST", [Param.new("zref", "", "json")]),
]

FunctionalTester.new("fixtures/javascript/fastify_zod_schema/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
