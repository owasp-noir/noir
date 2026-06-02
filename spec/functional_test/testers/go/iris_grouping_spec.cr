require "../../func_spec.cr"

# Iris route-registration shapes beyond the plain verb form, all
# previously missed (FN) or mis-prefixed:
#   - `app.Handle("METHOD", "/path", h)` method-first registration
#   - `app.HandleMany("GET POST", "/path", h)` fans out to one endpoint
#     per listed verb
#   - `app.PartyFunc("/x", func(p){...})` / `app.Party("/x", func(p){...})`
#     closure-scoped groups — the inner routes are called on the closure
#     param, so the prefix is applied via byte-range scoping (which also
#     stacks nested groups: `/pf` + `/admin` + `/stats`).
expected_endpoints = [
  Endpoint.new("/handle-get", "GET"),
  Endpoint.new("/handle-del", "DELETE"),
  Endpoint.new("/many", "GET"),
  Endpoint.new("/many", "POST"),
  Endpoint.new("/pf/inside", "GET"),
  Endpoint.new("/pf/create", "POST"),
  Endpoint.new("/pf/admin/stats", "GET"),
  Endpoint.new("/pc/x", "GET"),
  # Subdomain `admin.` is peeled to a clean path (not `/admin./settings`)
  # and carried on a `subdomain` tag.
  Endpoint.new("/settings", "GET"),
]

FunctionalTester.new("fixtures/go/iris_grouping/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
