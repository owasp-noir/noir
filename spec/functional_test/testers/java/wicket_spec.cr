require "../../func_spec.cr"

# wicketstuff-rest @MethodMapping handlers invoke a service; assert the
# 1-hop callees surface so the Wicket callee/ai-context path stays
# covered. The resource is mounted at both /scanned (@ResourcePath) and
# /api (mountResource), so callees ride along on both.
scanned_persons = Endpoint.new("/scanned/persons", "GET")
scanned_persons.push_callee(Callee.new("personService.findAll"))
scanned_delete = Endpoint.new("/scanned/persons/{personId}", "DELETE", [
  Param.new("personId", "", "path"),
])
scanned_delete.push_callee(Callee.new("personService.deleteById"))

# POST handler exercises wicketstuff-rest request-parameter annotations:
# @RequestBody → json body param, @RequestParam → query param. Asserted
# on both mount points (/scanned via @ResourcePath, /api via mountResource).
scanned_create = Endpoint.new("/scanned/persons", "POST", [
  Param.new("person", "", "json"),
  Param.new("notify", "", "query"),
])
scanned_create.push_callee(Callee.new("personService.save"))
api_create = Endpoint.new("/api/persons", "POST", [
  Param.new("person", "", "json"),
  Param.new("notify", "", "query"),
])

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
  scanned_persons,
  scanned_create,
  scanned_delete,
  Endpoint.new("/dashboards", "GET"),
  Endpoint.new("/api/persons", "GET"),
  api_create,
  Endpoint.new("/api/persons/{personId}", "DELETE", [
    Param.new("personId", "", "path"),
  ]),
  Endpoint.new("/lambda/status", "GET"),
  Endpoint.new("/lambda/items/{itemId}", "POST", [
    Param.new("itemId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/java/wicket/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"include_callee" => YAML::Any.new(true)}).perform_tests
