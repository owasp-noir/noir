require "../../func_spec.cr"

# Controller-style registration (`web.Router("/path", &Ctrl{}, "get:M")`)
# is Beego's dominant routing idiom. The mapping-less form fans out to
# every HTTP-verb method the controller implements; explicit mappings
# resolve to the listed methods. Callees come from walking the named
# controller method's body — the registration call doesn't pass the
# handler as an argument, so it's resolved by method name within the
# package (here every UserController method calls `c.Ctx.Output.Body`).
main = "spec/functional_test/fixtures/go/beego_controller/main.go"

expected_endpoints = [
  Endpoint.new("/users", "GET").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 30)) },
  Endpoint.new("/users", "POST").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 34)) },
  Endpoint.new("/users/profile", "GET").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 38)) },
  Endpoint.new("/users/update", "POST").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 42)) },
  Endpoint.new("/users/batch", "GET").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 46)) },
  Endpoint.new("/users/batch", "POST").tap { |ep| ep.push_callee(Callee.new("c.Ctx.Output.Body", main, 46)) },
]

FunctionalTester.new("fixtures/go/beego_controller/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
