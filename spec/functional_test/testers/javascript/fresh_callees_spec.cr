require "../../func_spec.cr"

list = Endpoint.new("/api/users", "GET")
list.push_callee(Callee.new("Response"))

create = Endpoint.new("/api/users", "POST")
create.push_callee(Callee.new("req.json"))
create.push_callee(Callee.new("JSON.stringify"))

show = Endpoint.new("/users/{id}", "GET")
show.push_callee(Callee.new("ctx.render"))

FunctionalTester.new("fixtures/javascript/fresh/", {
  :techs     => 1,
  :endpoints => 13,
}, [list, create, show], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
