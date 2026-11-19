require "../../func_spec.cr"

# Gin's documented context readers beyond `Query` / `PostForm`: the
# `Array` / `Map` / `Get` forms, `FormFile`, every read on a line, and the
# stdlib request behind the context.
expected_endpoints = [
  Endpoint.new("/a00-control", "GET", [Param.new("ok_query", "", "query"), Param.new("ok_default", "", "query"), Param.new("X-Ok", "", "header")]),
  Endpoint.new("/a01-query-collections", "GET", [Param.new("ids", "", "query"), Param.new("filter", "", "query"), Param.new("tags", "", "query")]),
  Endpoint.new("/a02-form-collections", "POST", [Param.new("colors", "", "form"), Param.new("names", "", "form")]),
  Endpoint.new("/a03-upload", "POST", [Param.new("avatar", "", "form")]),
  Endpoint.new("/a04-two-on-a-line", "GET", [Param.new("page", "", "query"), Param.new("size", "", "query")]),
  Endpoint.new("/a05-stdlib-request", "GET", [Param.new("raw_q", "", "query"), Param.new("raw_form", "", "query"), Param.new("raw_post", "", "form")]),
]

FunctionalTester.new("fixtures/go/gin_param_accessors/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
