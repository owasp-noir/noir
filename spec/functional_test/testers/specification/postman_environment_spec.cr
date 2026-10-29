require "../../func_spec.cr"

FunctionalTester.new("fixtures/specification/postman/environment/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/api/articles", "GET"),
]).perform_tests
