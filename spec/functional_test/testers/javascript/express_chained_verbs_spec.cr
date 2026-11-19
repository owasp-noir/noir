require "../../func_spec.cr"

# `router.get(...).post(...)`: Express returns the router from each verb,
# so every link registers a route. Only the first link was read.
FunctionalTester.new("fixtures/javascript/express_chained_verbs/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/api/items", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/items/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/one", "GET"),
  Endpoint.new("/api/two", "POST", [Param.new("title", "", "json")]),
]).perform_tests
