require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/cities", "POST", [
    Param.new("id", "", "json"),
    Param.new("name", "", "json"),
    Param.new("description", "", "json"),
    Param.new("location", "", "json"),
  ]),
  Endpoint.new("/cities/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("description", "", "json"),
    Param.new("location", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/spring_multimodule/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
