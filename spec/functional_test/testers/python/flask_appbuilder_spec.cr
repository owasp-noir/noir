require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v1/database/{pk}/connection", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/api/v1/database", "POST"),
  Endpoint.new("/annotationlayer/list/", "GET"),
  Endpoint.new("/annotationlayer/{pk}/annotation", "GET", [Param.new("pk", "", "path")]),
]

FunctionalTester.new("fixtures/python/flask_appbuilder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
