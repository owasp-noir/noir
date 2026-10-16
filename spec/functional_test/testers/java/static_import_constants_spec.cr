require "../../func_spec.cr"

# `import static pkg.Class.NAME` (or `.*`) brings a constant in under its bare
# name. It used to stay unresolved: a class-level `@RequestMapping(NAME + "/ops")`
# lost its whole prefix and every method was emitted root-relative
# (`POST /raft` instead of `POST /api/admin/ops/raft`), and a method-level
# `@GetMapping(NAME)` dropped the route.
expected_endpoints = [
  Endpoint.new("/api/admin/ops/raft", "POST"),
  Endpoint.new("/api/admin/ops/version", "GET"),
  Endpoint.new("/api/tasks/poll/{taskType}", "GET", [Param.new("taskType", "", "path")]),
  Endpoint.new("/api/admin/state/liveness", "GET"),
]

FunctionalTester.new("fixtures/java/static_import_constants/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
