require "../../func_spec.cr"

# Regression: the analyzer gated every file on the literal import path
# `github.com/gorilla/mux`, so a project using the API-compatible
# `github.com/minio/mux` fork reported zero routes. MinIO's own scan lost
# its whole S3 data plane this way.
expected_endpoints = [
  Endpoint.new("/objects/{object}", "GET", [
    Param.new("object", "", "path"),
  ]),
  Endpoint.new("/objects/{object}", "PUT", [
    Param.new("object", "", "path"),
  ]),
  Endpoint.new("/admin/heal", "DELETE"),
]

FunctionalTester.new("fixtures/go/mux_fork/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
