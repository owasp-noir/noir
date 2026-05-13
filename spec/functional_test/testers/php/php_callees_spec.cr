require "../../func_spec.cr"

search = Endpoint.new("/search.php", "GET", [
  Param.new("q", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserRepository::search", line: 3))
  ep.push_callee(Callee.new("render_json", line: 4))
end

create = Endpoint.new("/create.php", "POST", [
  Param.new("name", "", "form"),
]).tap do |ep|
  ep.push_callee(Callee.new("sanitize_name", line: 6))
  ep.push_callee(Callee.new("UserRepository::create", line: 7))
  ep.push_callee(Callee.new("AuditLog::write", line: 8))
  ep.push_callee(Callee.new("render_json", line: 9))
end

create_get = Endpoint.new("/create.php", "GET").tap do |ep|
  ep.push_callee(Callee.new("sanitize_name", line: 6))
  ep.push_callee(Callee.new("UserRepository::create", line: 7))
  ep.push_callee(Callee.new("AuditLog::write", line: 8))
  ep.push_callee(Callee.new("render_json", line: 9))
end

expected_endpoints = [
  search,
  create,
  create_get,
]

tester = FunctionalTester.new("fixtures/php/php_callees/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

describe "Pure PHP callee extraction" do
  it "keeps file-level callees to top-level calls" do
    endpoint = tester.app.endpoints.find { |e| e.method == "POST" && e.url == "/create.php" }
    endpoint.should_not be_nil

    if endpoint
      endpoint.callees.map { |callee| {callee.name, callee.line} }.should eq([
        {"sanitize_name", 6},
        {"UserRepository::create", 7},
        {"AuditLog::write", 8},
        {"render_json", 9},
      ])
    end
  end
end
