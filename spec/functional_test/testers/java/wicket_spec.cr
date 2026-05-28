require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/admin/**", "GET"),
  Endpoint.new("/assets/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/reports/{reportId}", "GET", [
    Param.new("reportId", "", "path"),
  ]),
  Endpoint.new("/legacy/**", "GET"),
  Endpoint.new("/downloads/{file}", "GET", [
    Param.new("file", "", "path"),
  ]),
  Endpoint.new("/products", "GET"),
  Endpoint.new("/orders/{orderId}", "GET", [
    Param.new("orderId", "", "path"),
  ]),
  Endpoint.new("/purchases/{orderId}", "GET", [
    Param.new("orderId", "", "path"),
  ]),
  Endpoint.new("/DefaultMountPage", "GET"),
]

FunctionalTester.new("fixtures/java/wicket/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
