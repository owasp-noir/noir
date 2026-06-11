require "../../func_spec.cr"

pages_endpoint = Endpoint.new("/api/users", "POST", [
  Param.new("page", "", "query"),
])
pages_endpoint.push_callee(Callee.new("parseUser", line: 6))
pages_endpoint.push_callee(Callee.new("serviceFactory().save", line: 7))
pages_endpoint.push_callee(Callee.new("AuditLog.write", line: 8))
pages_endpoint.push_callee(Callee.new("res.status().json", line: 10))
pages_endpoint.push_callee(Callee.new("serializeUser", line: 10))

pages_arrow_endpoint = Endpoint.new("/api/arrow", "GET", [
  Param.new("x-token", "", "header"),
])
pages_arrow_endpoint.push_callee(Callee.new("loadArrow", line: 6))
pages_arrow_endpoint.push_callee(Callee.new("res.json", line: 7))

pages_local_endpoint = Endpoint.new("/api/local", "DELETE", [
  Param.new("id", "", "query"),
])
pages_local_endpoint.push_callee(Callee.new("deleteLocal", line: 6))
pages_local_endpoint.push_callee(Callee.new("AuditLog.write", line: 7))
pages_local_endpoint.push_callee(Callee.new("res.status().end", line: 8))

app_get_endpoint = Endpoint.new("/api/orders/{id}", "GET", [
  Param.new("id", "", "path"),
  Param.new("session", "", "cookie"),
])
app_get_endpoint.push_callee(Callee.new("cookies().get", line: 7))
app_get_endpoint.push_callee(Callee.new("loadOrder", line: 8))
app_get_endpoint.push_callee(Callee.new("NextResponse.json", line: 10))
app_get_endpoint.push_callee(Callee.new("formatOrder", line: 10))

app_post_endpoint = Endpoint.new("/api/orders/{id}", "POST", [
  Param.new("id", "", "path"),
])
app_post_endpoint.push_callee(Callee.new("request.json", line: 14))
app_post_endpoint.push_callee(Callee.new("serviceFactory().create", line: 15))
app_post_endpoint.push_callee(Callee.new("AuditLog.write", line: 16))
app_post_endpoint.push_callee(Callee.new("NextResponse.json", line: 18))

app_alias_endpoint = Endpoint.new("/api/reports", "GET")
app_alias_endpoint.push_callee(Callee.new("reportService.list", line: 4))
app_alias_endpoint.push_callee(Callee.new("AuditLog.write", line: 5))
app_alias_endpoint.push_callee(Callee.new("NextResponse.json", line: 6))

create_action_endpoint = Endpoint.new("/createUser", "POST", [
  Param.new("name", "", "form"),
])
create_action_endpoint.push_callee(Callee.new("formData.get", line: 4))
create_action_endpoint.push_callee(Callee.new("buildUser", line: 5))
create_action_endpoint.push_callee(Callee.new("saveUser", line: 6))
create_action_endpoint.push_callee(Callee.new("AuditLog.write", line: 7))
create_action_endpoint.push_callee(Callee.new("revalidateUser", line: 9))

delete_action_endpoint = Endpoint.new("/deleteUser", "POST", [
  Param.new("id", "", "body"),
])
delete_action_endpoint.push_callee(Callee.new("deleteUserById", line: 13))
delete_action_endpoint.push_callee(Callee.new("redirectToUsers", line: 14))

FunctionalTester.new("fixtures/javascript/nextjs_callees/", {
  :techs     => 1,
  :endpoints => 8,
}, [
  pages_endpoint,
  pages_arrow_endpoint,
  pages_local_endpoint,
  app_get_endpoint,
  app_post_endpoint,
  app_alias_endpoint,
  create_action_endpoint,
  delete_action_endpoint,
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "Next.js callee source attribution" do
  it "uses aliased route handlers and server-action export lines" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs_callees/")])
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    report = app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/api/reports" }
    report.details.code_paths.first.line.should eq(3)

    post = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/api/orders/{id}" }
    post.details.code_paths.first.line.should eq(13)

    create_action = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/createUser" }
    create_action.details.code_paths.first.line.should eq(3)

    delete_action = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/deleteUser" }
    delete_action.details.code_paths.first.line.should eq(12)
  end
end
