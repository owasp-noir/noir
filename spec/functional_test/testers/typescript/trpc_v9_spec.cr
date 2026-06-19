require "../../func_spec.cr"

# tRPC v9 chain routers used `.query("name", { input, resolve })` and
# `.merge("prefix.", childRouter)` instead of v10's object router map.
# min-todo is an OSS example that uses this shape.
expected_endpoints = [
  Endpoint.new("/api/trpc/todo.get-all", "GET", [
    Param.new("sortBy", "", "query"),
  ]),
  Endpoint.new("/api/trpc/todo.get", "GET", [
    Param.new("todoId", "", "query"),
  ]),
  Endpoint.new("/api/trpc/todo.add", "POST", [
    Param.new("input", "", "body"),
  ]),
  Endpoint.new("/api/trpc/todo.delete", "POST", [
    Param.new("id", "", "body"),
  ]),
]

FunctionalTester.new("fixtures/typescript/trpc_v9/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("ts_trpc"),
}).perform_tests
