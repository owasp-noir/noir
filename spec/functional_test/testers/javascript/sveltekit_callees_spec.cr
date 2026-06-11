require "../../func_spec.cr"

list_endpoint = Endpoint.new("/api/users", "GET")
list_endpoint.push_callee(Callee.new("url.searchParams.get", line: 4))
list_endpoint.push_callee(Callee.new("listUsers", line: 5))
list_endpoint.push_callee(Callee.new("AuditLog.write", line: 6))
list_endpoint.push_callee(Callee.new("json", line: 8))
list_endpoint.push_callee(Callee.new("serializeUsers", line: 8))

create_endpoint = Endpoint.new("/api/users", "POST")
create_endpoint.push_callee(Callee.new("request.json", line: 12))
create_endpoint.push_callee(Callee.new("serviceFactory().create", line: 13))
create_endpoint.push_callee(Callee.new("AuditLog.write", line: 14))
create_endpoint.push_callee(Callee.new("json", line: 16))

update_endpoint = Endpoint.new("/api/users/{id}", "PUT", [
  Param.new("id", "", "path"),
])
update_endpoint.push_callee(Callee.new("request.json", line: 4))
update_endpoint.push_callee(Callee.new("updateUser", line: 5))
update_endpoint.push_callee(Callee.new("AuditLog.write", line: 6))
update_endpoint.push_callee(Callee.new("json", line: 8))

delete_endpoint = Endpoint.new("/api/users/{id}", "DELETE", [
  Param.new("id", "", "path"),
])
delete_endpoint.push_callee(Callee.new("deleteUserById", line: 12))
delete_endpoint.push_callee(Callee.new("json", line: 13))

FunctionalTester.new("fixtures/javascript/sveltekit_callees/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  list_endpoint,
  create_endpoint,
  update_endpoint,
  delete_endpoint,
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "SvelteKit callee source attribution" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "uses direct and aliased exported API handler lines" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/sveltekit_callees/")])
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    list = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users" }
    list.details.code_paths.first.line.should eq(3)

    create = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    create.details.code_paths.first.line.should eq(11)

    update = app.endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/api/users/{id}" }
    update.details.code_paths.first.line.should eq(3)

    delete = app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/api/users/{id}" }
    delete.details.code_paths.first.line.should eq(11)
  end
end
