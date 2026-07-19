require "../../func_spec.cr"

# ColdBox declares routes in config/Router.cfc. Two pieces of context
# live outside that file and are resolved by the analyzer: a module's
# routes mount under its ModuleConfig entryPoint, and a verb-agnostic
# `route()` takes its verbs from the target handler's allowedMethods.
expected_endpoints = [
  # `route( "/", "main.index" )` — main has no allowedMethods, so GET.
  Endpoint.new("/", "GET"),

  # Explicit verb helpers.
  Endpoint.new("/whoami", "GET"),
  Endpoint.new("/login", "POST"),

  # `resources( "photos" )` expands to the standard REST set, with PATCH
  # registered alongside PUT for the update action.
  Endpoint.new("/photos", "GET"),
  Endpoint.new("/photos", "POST"),
  Endpoint.new("/photos/new", "GET"),
  Endpoint.new("/photos/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/:id", "DELETE", [Param.new("id", "", "path")]),

  # Named arguments, `#sitePrefix#` resolved from a local, and
  # `except = "new,edit"` dropping those two actions.
  Endpoint.new("/sites/:site/comments", "GET", [Param.new("site", "", "path")]),
  Endpoint.new("/sites/:site/comments", "POST", [Param.new("site", "", "path")]),
  Endpoint.new("/sites/:site/comments/:id", "GET", [
    Param.new("site", "", "path"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/sites/:site/comments/:id", "PUT"),
  Endpoint.new("/sites/:site/comments/:id", "PATCH"),
  Endpoint.new("/sites/:site/comments/:id", "DELETE"),

  # Fluent `.to()` target.
  Endpoint.new("/render/:format", "GET", [Param.new("format", "", "path")]),

  # Inline placeholder constraints (`:id-numeric{2}`) must not leak into
  # the URL, and the per-function `allowedMethods` attribute supplies
  # both verbs.
  Endpoint.new("/legacy/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/legacy/:id", "POST", [Param.new("id", "", "path")]),

  # A module's routes mount under its ModuleConfig entryPoint.
  Endpoint.new("/api/v1/status", "GET"),
]

FunctionalTester.new("fixtures/cfml/coldbox/", {
  :techs     => 2, # Detection still sees cfml_coldbox and cfml_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
