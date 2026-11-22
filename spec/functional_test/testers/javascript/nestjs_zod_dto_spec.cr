require "../../func_spec.cr"

# #3309: a nestjs-zod `createZodDto(Schema)` DTO has the fields of its
# `z.object({...})` schema.
expected_endpoints = [
  Endpoint.new("/items", "POST", [Param.new("name", "", "body"), Param.new("price", "", "body")]),
  Endpoint.new("/items", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/items", "PUT", [Param.new("name", "", "body"), Param.new("price", "", "body")]),
  Endpoint.new("/items/published", "POST", [Param.new("display-label", "", "body"), Param.new("timestamp", "", "body")]),
  Endpoint.new("/items/filtered", "GET", [Param.new("display-label", "", "query"), Param.new("nested", "", "query"), Param.new("region", "", "query")]),
  Endpoint.new("/items/dynamic", "PUT", [Param.new("body", "", "body")]),
]

FunctionalTester.new("fixtures/javascript/nestjs_zod_dto/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
