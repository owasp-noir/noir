require "../../func_spec.cr"

fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

expected_endpoints = [] of Endpoint

# app:get / app:post / app:put / app:delete / app:patch — explicit verbs.
expected_endpoints << Endpoint.new("/", "GET")
expected_endpoints << Endpoint.new("/users", "GET")
expected_endpoints << Endpoint.new("/login", "POST")
expected_endpoints << Endpoint.new("/profile", "PUT")
expected_endpoints << Endpoint.new("/items/:id", "DELETE", [Param.new("id", "", "path")])
expected_endpoints << Endpoint.new("/notes/:id", "PATCH", [Param.new("id", "", "path")])
expected_endpoints << Endpoint.new("/files/*splat", "GET", [Param.new("splat", "", "path")])

# app:match — falls back to all verbs.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/about", m) }
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/users/:id", m, [Param.new("id", "", "path")])
end

# Named-route verb form — `app:get(name, "/path", handler)`.
expected_endpoints << Endpoint.new("/named", "GET")
expected_endpoints << Endpoint.new("/named/users", "POST")

# Custom Application variable name — `local users_app = lapis.Application()`.
expected_endpoints << Endpoint.new("/api/users", "GET")
expected_endpoints << Endpoint.new("/api/users", "POST")
expected_endpoints << Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")])

# Application table style — `["/admin/..."] = ...` falls back to all verbs.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/admin/dashboard", m) }
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/admin/users", m) }

# MoonScript actions.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/moon", m) }
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/moon/users/:id", m, [Param.new("id", "", "path")])
end

FunctionalTester.new("fixtures/lua/lapis/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
