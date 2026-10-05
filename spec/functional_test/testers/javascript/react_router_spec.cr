require "../../func_spec.cr"

# `app/routes.ts` drives the URLs; the file convention is off, so
# `routes/home.tsx` is `/` (its `index()`), never `/home`.
config_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  # `layout()` adds no path segment and is not itself a route.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/login", "PUT"),
  Endpoint.new("/login", "PATCH"),
  Endpoint.new("/login", "DELETE"),
  # `prefix("api", ...)`; a resource module serves only what it exports.
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/docs/{splat}", "GET", [Param.new("splat", "", "path")]),
  Endpoint.new("/{lang}/blog", "GET", [Param.new("lang", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/react_router/", {
  :techs     => 1,
  :endpoints => config_endpoints.size,
}, config_endpoints).perform_tests

# `...(await flatRoutes())` turns the Remix `app/routes/` convention on
# beside the explicit `route()` entries.
flat_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/", "GET"),
  # Folder route: `routes/dashboard/route.tsx`; `chart.tsx` beside it is not a route.
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/react_router_flat/", {
  :techs     => 1,
  :endpoints => flat_endpoints.size,
}, flat_endpoints).perform_tests
