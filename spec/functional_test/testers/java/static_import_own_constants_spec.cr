require "../../func_spec.cr"

# A wildcard `import static pkg.Class.*` brings every constant of that class
# in under its bare name, but a field of the file's own with the same name is
# the nearer declaration: `LocalResource.BASE = "/local"` must beat
# `Commons.BASE = "/commons"`. Names only the import supplies (`ADMIN`,
# and `BASE` in a file with no field of that name) still resolve.
expected_endpoints = [
  Endpoint.new("/local/m", "GET"),
  Endpoint.new("/local/admin/o", "GET"),
  Endpoint.new("/commons/imp/x", "GET"),
]

FunctionalTester.new("fixtures/java/static_import_own_constants/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
