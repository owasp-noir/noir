require "../../func_spec.cr"

# Root `api/` modules in a project depending on `@vercel/node`. `_lib/`, test
# files and non-root `api` dirs are not deployed as functions.
FunctionalTester.new("fixtures/javascript/vercel_functions/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/api/hello", "ANY", [Param.new("name", "", "query")]),
  Endpoint.new("/api", "ANY", [Param.new("session", "", "cookie")]),
  # `req.query.id` is the `[id]` segment, so it is reported once, as a path param.
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-csrf-token", "", "header"),
    Param.new("displayName", "", "json"),
  ]),
  Endpoint.new("/api/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("x-csrf-token", "", "header"),
    Param.new("displayName", "", "json"),
  ]),
  Endpoint.new("/api/v2/orders", "GET", [Param.new("status", "", "query")]),
  Endpoint.new("/api/v2/orders", "POST", [
    Param.new("sku", "", "json"),
    Param.new("quantity", "", "json"),
  ]),
]).perform_tests

# A Next.js app on Vercel: `pages/api` and `app/api` stay with the Next.js
# analyzer and are not reported a second time as Vercel Functions.
FunctionalTester.new("fixtures/javascript/vercel_functions_nextjs/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/hello", "GET", [Param.new("name", "", "query")]),
]).perform_tests
