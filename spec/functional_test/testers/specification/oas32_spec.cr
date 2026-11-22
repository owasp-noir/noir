require "../../func_spec.cr"

# OAS 3.2 additionalOperations inherit path-level parameters.
FunctionalTester.new("fixtures/specification/oas3/oas32/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/trips/{id}", "SUBSCRIBE", [
    Param.new("id", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
  Endpoint.new("/trips/{id}", "LINK", [
    Param.new("id", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
  Endpoint.new("/stations", "GET"),
  Endpoint.new("/document", "PUT", [
    Param.new("docType", "", "json"),
    Param.new("headline", "", "json"),
  ]),
  Endpoint.new("/pet", "PUT", [
    Param.new("petType", "", "json"),
    Param.new("huntingSkill", "", "json"),
  ]),
  Endpoint.new("/vehicle", "PUT", [
    Param.new("vehicleType", "", "json"),
    Param.new("gears", "", "json"),
    Param.new("doors", "", "json"),
  ]),
]).perform_tests
