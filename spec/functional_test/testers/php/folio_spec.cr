require "../../func_spec.cr"

# Folio pages under each `Folio::path(...)` mount become GET routes:
# `index` is the directory, `[User]` / `[...slug]` are path params. Views
# outside a mount (and under a commented-out mount) are not endpoints.
FunctionalTester.new("fixtures/php/folio/", {
  :techs     => 3,
  :endpoints => 7,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{user}", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/admin/settings", "GET"),
  Endpoint.new("/docs/{slug}", "GET", [Param.new("slug", "", "path")]),
  # `Folio::domain(...)->path(...)` is a mount too.
  Endpoint.new("/tenant/dashboard", "GET"),
]).perform_tests
