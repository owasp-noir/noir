require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/articles/", "POST"),
  Endpoint.new("/articles/search", "GET"),
  Endpoint.new("/articles/{articleSlug:[a-z-]+}", "GET", [Param.new("articleSlug", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "GET", [Param.new("articleID", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "PUT", [Param.new("articleID", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "DELETE", [Param.new("articleID", "", "path")]),
  Endpoint.new("/admin/", "GET"),
  Endpoint.new("/admin/accounts", "GET"),
  Endpoint.new("/accounts", "GET"),
]

FunctionalTester.new("fixtures/go/chi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
