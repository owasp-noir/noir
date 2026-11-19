require "../../func_spec.cr"

# Routes decorated on an app or router imported from the module that
# declares it are served under that instance's mounts.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/login", "POST", [Param.new("username", "", "query"), Param.new("password", "", "query")]),
  Endpoint.new("/api/items/{item_id}", "GET", [Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/python/fastapi_imported_instance/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
