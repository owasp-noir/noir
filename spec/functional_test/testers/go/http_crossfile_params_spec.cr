require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("next", "", "query"),
  ]),
  Endpoint.new("/v1/entries", "GET", [
    Param.new("status", "", "query"),
    Param.new("starred", "", "query"),
    # The handler's `r.PathValue("entryID")` is not a path param here: the
    # pattern `GET /v1/entries` has no `{entryID}` wildcard (#3307).
    Param.new("before", "", "query"),
  ]),
  Endpoint.new("/v1/entries", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Trace-ID", "", "header"),
    Param.new("title", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/go/http_crossfile_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
