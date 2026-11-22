require "../../func_spec.cr"

# Methods on the API root (`!GetAtt Api.RootResourceId`, YAML and JSON),
# `AWS::ApiGatewayV2::Route` keys (`$default` selects no path), and the
# inline OpenAPI `DefinitionBody` of a SAM API.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/", "POST"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/items/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/inline-openapi", "POST"),
  Endpoint.new("/inline-any", "ANY"),
]

FunctionalTester.new("fixtures/specification/aws_cloudformation_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
