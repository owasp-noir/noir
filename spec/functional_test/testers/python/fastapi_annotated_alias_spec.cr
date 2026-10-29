require "../../func_spec.cr"

# Regression (#3294): a handler param typed with a module-level
# `Annotated[...]` alias reads as the expression it names: an imported
# `Depends()` alias (one line and multi-line, its dependency resolved in
# the file that assigns it), a same-file one, a `Query()` alias, and a
# `typing_extensions.Annotated` one reached through a star import.
common = [
  Param.new("page", "1", "query"),
  Param.new("itemsPerPage", "5", "query"),
  Param.new("q", "", "query"),
]

expected_endpoints = [
  Endpoint.new("/aliased", "GET", common),
  Endpoint.new("/multiline", "GET", common),
  Endpoint.new("/local", "GET", [Param.new("token", "", "query"), Param.new("maxItems", "", "query")]),
  Endpoint.new("/tenant", "GET", [Param.new("x-tenant-id", "", "header")]),
]

FunctionalTester.new("fixtures/python/fastapi_annotated_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
