require "../../func_spec.cr"

# Covers the sub-application route shapes real Lapis projects use:
#   * `app.path` mount prefixes prepended to every route
#   * empty patterns that resolve to the bare prefix
#   * Lua-pattern param constraints (`:id[%d]`) stripped to the name
#   * optional groups (`(/page/:page)`) peeled to the required base
#   * inline `respond_to({ GET = ..., PUT = ... })` verb narrowing
#   * MoonScript `respond_to`/wrapped-arrow class actions
fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

expected_endpoints = [] of Endpoint

# users.lua — mounted at `/api/users`.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/api/users", m) }
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/api/users/:id", m, [Param.new("id", "", "path")])
end
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/api/users/:id/posts", m, [Param.new("id", "", "path")])
end
["GET", "PUT"].each do |m|
  expected_endpoints << Endpoint.new("/api/users/:id/settings", m, [Param.new("id", "", "path")])
end

# admin.lua — mounted at `/admin`, custom application variable.
expected_endpoints << Endpoint.new("/admin/dashboard", "GET")
expected_endpoints << Endpoint.new("/admin/stats/:metric", "GET", [Param.new("metric", "", "path")])

# app.moon — MoonScript class actions.
["GET", "POST"].each { |m| expected_endpoints << Endpoint.new("/profile", m) }
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/account/:id", m, [Param.new("id", "", "path")])
end
# Bare key with a handler-expression value (`require(...).make!`).
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/console", m) }

# dashboard.moon — MoonScript controller with a `@path: "/dashboard"` prefix.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/dashboard/overview", m) }
["GET", "DELETE"].each do |m|
  expected_endpoints << Endpoint.new("/dashboard/stats/:id", m, [Param.new("id", "", "path")])
end

FunctionalTester.new("fixtures/lua/lapis_subapp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
