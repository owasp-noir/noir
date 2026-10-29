require "../../func_spec.cr"

# PocketBase bind functions receive the `/api` group as an argument (the
# second one in `BindBackupApi(app, api)`), typed with a generic
# `*router.RouterGroup[*core.RequestEvent]`.
expected_endpoints = [
  Endpoint.new("/api/backups", "GET"),
  Endpoint.new("/api/backups/{key}", "DELETE"),
  Endpoint.new("/api/first", "GET"),
  Endpoint.new("/api/sql", "POST"),
  Endpoint.new("/api/direct", "GET"),
]

FunctionalTester.new("fixtures/go/pocketbase_group_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
