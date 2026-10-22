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

  # `group( { pattern : "/admin" }, ... )` prefixes the routes declared in
  # its closure, and `withAction` names one action per verb.
  Endpoint.new("/admin/reports", "GET"),
  Endpoint.new("/admin/reports/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/reports/:id", "DELETE", [Param.new("id", "", "path")]),

  # A namespace group mounts where a route puts it. The mount itself
  # (`route( "/v2" ).toNamespaceRouting( "v2" )`) is not a route.
  Endpoint.new("/v2/ping", "GET"),

  # `except = skipped` passes a local by name, so `new` and `edit` are
  # dropped just as they would be for a literal.
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/tags", "POST"),
  Endpoint.new("/tags/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/tags/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/tags/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/tags/:id", "DELETE", [Param.new("id", "", "path")]),

  # A CFML framework owns the `.cfm` page surface, but `access="remote"`
  # methods stay HTTP-callable and no framework analyzer emits them, so
  # the generic analyzer runs alongside in components-only mode.
  Endpoint.new("/remote/Proxy.cfc?method=ping", "GET", [Param.new("token", "", "query")]),
  Endpoint.new("/remote/Proxy.cfc?method=ping", "POST", [Param.new("token", "", "form")]),
]

FunctionalTester.new("fixtures/cfml/coldbox/", {
  :techs     => 2, # Detection still sees cfml_coldbox and cfml_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
