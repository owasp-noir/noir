require "../../func_spec.cr"

# invidious-style Kemal routing: routes dispatch to `Controller, :action`
# handlers defined in other files (no inline `do … end` block). The callees
# must be resolved cross-file through the action index, including routes
# whose controller is named via a compile-time macro variable.
home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 3))
  ep.push_callee(Callee.new("env.redirect", line: 4))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("env.params.json", line: 8))
  ep.push_callee(Callee.new("UserService.create", line: 9))
end

# `{{namespace = Routes::API}}` + `{{namespace}}::Items` resolves to
# `Routes::API::Items`, so this route still carries its handler's callees.
items_show = Endpoint.new("/api/items/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("env.params.url", line: 3))
  ep.push_callee(Callee.new("ItemLookup.find", line: 4))
end

expected_endpoints = [
  home,
  users_create,
  items_show,
]

FunctionalTester.new("fixtures/crystal/kemal_controller_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_kemal"),
}).perform_tests
