require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 7))
  ep.push_callee(Callee.new("HomePresenter.render", line: 8))
  ep.push_callee(Callee.new("respond", line: 9))
end

users = Endpoint.new("/api/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("UserSearch.list", line: 3))
  ep.push_callee(Callee.new("UserPresenter.render", line: 4))
  ep.push_callee(Callee.new("respond", line: 5))
end

user_detail = Endpoint.new("/api/users/<int:id>", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserLookup.find", line: 4))
  ep.push_callee(Callee.new("UserPresenter.render", line: 5))
  ep.push_callee(Callee.new("respond", line: 5))
end

admin_reports = Endpoint.new("/admin/reports", "GET").tap do |ep|
  ep.push_callee(Callee.new("ReportService.latest", line: 4))
  ep.push_callee(Callee.new("ReportSerializer.render", line: 5))
  ep.push_callee(Callee.new("respond", line: 5))
end

absolute_reports = Endpoint.new("/absolute/reports", "GET").tap do |ep|
  ep.push_callee(Callee.new("ReportService.latest", line: 4))
  ep.push_callee(Callee.new("ReportSerializer.render", line: 5))
  ep.push_callee(Callee.new("respond", line: 5))
end

macro_route = Endpoint.new("/macro", "GET").tap do |ep|
  ep.push_callee(Callee.new("MacroService.call", line: 4))
  ep.push_callee(Callee.new("MacroPresenter.render", line: 5))
  ep.push_callee(Callee.new("respond", line: 5))
end

expected_endpoints = [
  home,
  users,
  user_detail,
  admin_reports,
  absolute_reports,
  macro_route,
]

FunctionalTester.new("fixtures/crystal/marten_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_marten"),
}).perform_tests
