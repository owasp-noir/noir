require "../../func_spec.cr"

# Kratos (https://go-kratos.dev/) HTTP routes come from `protoc-gen-go-http`
# generated `*_http.pb.go` files. The fixture mixes both codegen shapes in
# the wild:
#   - api/todo/v1/todo_http.pb.go    — v2.x verb-shortcut style (`r.POST(...)`)
#   - api/greeter/v1/greeter_http.pb.go — v3+ method-first style (`r.Handle("GET", ...)`)
#
# It also carries a sibling Gin router (pkg/adminui/router.go) in the same
# module that does NOT import Kratos' transport/http package. That proves
# the Kratos analyzer's import-marker gate keeps it from claiming a route
# registered by a different framework in the same repository (analyzer
# project scoping, #2417-2432) — and that Gin, in turn, doesn't touch the
# Kratos-generated files.
expected_endpoints = [
  Endpoint.new("/v1/todos/create", "POST", [
    Param.new("body", "", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("srv.CreateTodo"))
  end,

  Endpoint.new("/v1/todos/{id}", "GET", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("srv.GetTodo"))
  end,

  Endpoint.new("/v1/todos/update", "PUT", [
    Param.new("body", "", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("srv.UpdateTodo"))
  end,

  Endpoint.new("/v1/todos/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("srv.DeleteTodo"))
  end,

  Endpoint.new("/helloworld/{name}", "GET", [
    Param.new("name", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("srv.SayHello"))
  end,

  # Gin route from pkg/adminui/router.go — must surface under go_gin, not
  # go_kratos, and must not be duplicated.
  Endpoint.new("/admin/ping", "GET"),
]

FunctionalTester.new("fixtures/go/kratos/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
