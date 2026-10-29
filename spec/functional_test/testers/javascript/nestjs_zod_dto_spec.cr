require "../../func_spec.cr"

# #3309: a nestjs-zod `createZodDto(Schema)` DTO has the fields of its
# `z.object({...})` schema.
expected_endpoints = [
  Endpoint.new("/items", "POST", [Param.new("name", "", "body"), Param.new("price", "", "body")]),
  Endpoint.new("/items", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/items", "PUT", [Param.new("name", "", "body"), Param.new("price", "", "body")]),
]

FunctionalTester.new("fixtures/javascript/nestjs_zod_dto/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
