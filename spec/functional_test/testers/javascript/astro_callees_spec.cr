require "../../func_spec.cr"

list = Endpoint.new("/api/users", "GET")
list.push_callee(Callee.new("JSON.stringify"))

create = Endpoint.new("/api/users", "POST")
create.push_callee(Callee.new("request.json"))
create.push_callee(Callee.new("JSON.stringify"))

update = Endpoint.new("/api/users/{id}", "PUT")
update.push_callee(Callee.new("request.json"))
update.push_callee(Callee.new("JSON.stringify"))

FunctionalTester.new("fixtures/javascript/astro/", {
  :techs     => 1,
  :endpoints => 15,
}, [list, create, update], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
