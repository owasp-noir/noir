require "../../func_spec.cr"

all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

expected_endpoints = [] of Endpoint

# Direct route on the application object (`app:get("/", ...)`).
expected_endpoints << Endpoint.new("/", "GET")

# In-file router mount: `app:use("/api", apiRouter())` with a same-file
# `apiRouter = lor:Router()`.
expected_endpoints << Endpoint.new("/api/ping", "GET")

# Cross-file mount prefix: routes declared in app/routes/auth.lua are mounted
# under `/auth` by app/router.lua.
expected_endpoints << Endpoint.new("/auth/login", "GET")
expected_endpoints << Endpoint.new("/auth/login", "POST")
expected_endpoints << Endpoint.new("/auth/logout", "GET")

# Cross-file mount prefix `/todo`, including verbs, a path param, a relative
# (no leading slash) path, and `:all`.
expected_endpoints << Endpoint.new("/todo/complete", "POST")
expected_endpoints << Endpoint.new("/todo/add", "PUT")
expected_endpoints << Endpoint.new("/todo/delete", "DELETE")
expected_endpoints << Endpoint.new("/todo/find/:filter", "GET", [Param.new("filter", "", "path")])
expected_endpoints << Endpoint.new("/todo/index", "POST")
all_methods.each { |m| expected_endpoints << Endpoint.new("/todo/status", m) }

FunctionalTester.new("fixtures/lua/lor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
