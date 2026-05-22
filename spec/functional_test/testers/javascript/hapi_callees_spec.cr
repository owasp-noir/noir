require "../../func_spec.cr"

destroy = Endpoint.new("/users/{id}", "DELETE")
destroy.push_callee(Callee.new("h.response().code"))

FunctionalTester.new("fixtures/javascript/hapi/", {
  :techs     => 1,
  :endpoints => 12,
}, [destroy], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
