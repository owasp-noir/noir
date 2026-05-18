require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/", "GET"),
  Endpoint.new("/api/posts", "GET", [
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/posts/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/hono_cross_file_mount/", {
  :techs => 1,
}, expected_endpoints).perform_tests
