require "../../func_spec.cr"

# Decorators read off the TypeScript AST: route-looking text inside a string
# or a comment is not a route or a controller, a `@Version(\n '2',\n)` split
# over lines still versions its route, a `)` inside a string argument does
# not end it, and `@UploadedFile(pipe)` is the upload field like
# `@UploadedFile()`.
expected_endpoints = [
  Endpoint.new("/v1/reports", "GET", [Param.new("sort", "", "query")]),
  Endpoint.new("/v2/reports/:id", "GET", [Param.new("id", "", "path"), Param.new("fields)", "", "query")]),
  Endpoint.new("/v1/reports", "POST", [Param.new("title", "", "body"), Param.new("tags", "", "body")]),
  Endpoint.new("/v1/reports/upload", "POST", [Param.new("file", "", "body")]),
]

FunctionalTester.new("fixtures/typescript/nestjs_decorator_ast/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
