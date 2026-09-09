require "../../func_spec.cr"

# `r.Mount("/api/v1", apiv1.Routes())` where `Routes` is declared in
# another package: the mount prefix must reach every route the target
# registers (including a nested `Mount` inside it), and a root mount
# (`r.Mount("/", web.Routes())`) must not double the slash. Before this
# fixture every gitea API route was reported without its `/api/v1`.
expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/metrics", "GET"),
  Endpoint.new("/api/v1/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}", "GET", [Param.new("owner", "", "path")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}/issues", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/api/v1/admin/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/go/chi_crosspkg_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
