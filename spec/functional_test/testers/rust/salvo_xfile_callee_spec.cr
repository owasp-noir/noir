require "../../func_spec.cr"

# Cross-file handler enrichment: the route in main.rs references
# `handler::create_user`, whose `#[handler]` body lives in handler.rs. A
# project-wide handler index supplies the params (req.parse_json -> json
# body, req.header::<&str> -> header) and callees from that other file, so
# the endpoint is no longer left with zero params/callees.
create_user = Endpoint.new("/api/users", "POST", [
  Param.new("body", "", "json"),
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.parse_json", line: 5))
  ep.push_callee(Callee.new("req.header", line: 6))
  ep.push_callee(Callee.new("UserService::insert", line: 7))
  ep.push_callee(Callee.new("res.render", line: 8))
end

FunctionalTester.new("fixtures/rust/salvo_xfile_callee/", {
  :techs     => 1,
  :endpoints => 1,
}, [create_user], {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_salvo"),
}).perform_tests
