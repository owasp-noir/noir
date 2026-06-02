require "../../func_spec.cr"

# Regression test: gorilla/mux handlers are almost always method values
# (`a.ListUsers`) or wrapped method values (`mid.Use(as.Foo, ...)` in
# gophish). Both used to yield zero callees. Method-value handlers now
# resolve through the package method-body map, and wrapper calls are
# peeled to their underlying handler.
#
# Coverage:
#   - GET /users      — bare method-value handler `a.ListUsers`
#                       (callees `fetchUsers`, `w.Write`).
#   - GET /users/{id} — wrapped method-value handler `wrap(a.GetUser)`
#                       (callee `mux.Vars` from the unwrapped method body).
expected_endpoints = [
  Endpoint.new("/users", "GET").tap do |ep|
    ep.push_callee(Callee.new("fetchUsers"))
    ep.push_callee(Callee.new("w.Write"))
  end,
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("mux.Vars"))
  end,
]

FunctionalTester.new("fixtures/go/mux_method_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
