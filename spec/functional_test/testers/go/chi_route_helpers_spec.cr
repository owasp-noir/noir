require "../../func_spec.cr"

# A same-file function (or closure variable) that takes the router as a
# parameter registers its routes wherever it is called, under the
# caller's prefix. Before this fixture gitea's `addProjectRoutes(m, ...)`
# — called from the user, org and repo groups — was reported once, at
# the prefix-less `/{id}/columns`, which is a path nothing serves.
# A helper nobody calls keeps its historical prefix-less routes.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/orgs/{org}/projects", "GET", [Param.new("org", "", "path")]),
  Endpoint.new("/orgs/{org}/projects/{id}/", "GET", [Param.new("id", "", "path"), Param.new("org", "", "path")]),
  Endpoint.new("/orgs/{org}/projects/{id}/", "DELETE", [Param.new("id", "", "path"), Param.new("org", "", "path")]),
  Endpoint.new("/orgs/{org}/secrets", "GET", [Param.new("org", "", "path")]),
  Endpoint.new("/repos/{owner}/{repo}/projects", "GET", [Param.new("owner", "", "path"), Param.new("repo", "", "path")]),
  Endpoint.new("/repos/{owner}/{repo}/projects/{id}/", "GET", [Param.new("id", "", "path"), Param.new("owner", "", "path"), Param.new("repo", "", "path")]),
  Endpoint.new("/repos/{owner}/{repo}/projects/{id}/", "DELETE", [Param.new("id", "", "path"), Param.new("owner", "", "path"), Param.new("repo", "", "path")]),
  Endpoint.new("/orphan", "GET"),
]

FunctionalTester.new("fixtures/go/chi_route_helpers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
