require "../../func_spec.cr"

# The Fresh 2 starter (`deno run -A jsr:@fresh/init`): deno.json maps
# `fresh` to `jsr:@fresh/core`, file routes wrap their handler object in
# `define.handlers({ ... })`, and `main.ts` adds `app.get(...)` beside
# `app.fsRoutes()`.
FunctionalTester.new("fixtures/javascript/fresh2/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/api2/:name", "GET", [Param.new("name", "", "path")]),
]).perform_tests
