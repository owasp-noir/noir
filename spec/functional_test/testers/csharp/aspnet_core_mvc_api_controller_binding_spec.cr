require "../../func_spec.cr"

# `[ApiController]` infers the binding source of a parameter without
# `[FromX]`: a complex type from the JSON body, an upload from the form,
# anything else from the query string. A plain MVC controller keeps form
# binding for the same parameter.
expected_endpoints = [
  Endpoint.new("/Legacy/Save", "POST", [
    Param.new("Id", "", "form"), Param.new("Name", "", "form"), Param.new("IsComplete", "", "form"),
  ]),
  Endpoint.new("/api/TodoItems", "POST", [
    Param.new("id", "", "json"), Param.new("name", "", "json"), Param.new("isComplete", "", "json"),
  ]),
  Endpoint.new("/api/TodoItems/{id}", "PUT", [
    Param.new("id", "", "path"), Param.new("id", "", "json"), Param.new("name", "", "json"), Param.new("isComplete", "", "json"),
  ]),
  Endpoint.new("/api/TodoItems/{id}/complete", "POST", [Param.new("id", "", "path"), Param.new("notify", "", "query")]),
  Endpoint.new("/api/TodoItems/upload", "POST", [Param.new("file", "", "form"), Param.new("note", "", "query")]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_api_controller_binding/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC [ApiController] binding inference", tags: "functional" do
  it "reports exactly the inferred params" do
    params = ->(method : String, url : String) do
      tester.app.endpoints.find! { |e| e.method == method && e.url == url }.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!
    end
    params.call("POST", "/api/TodoItems").should eq(["id:json", "isComplete:json", "name:json"])
    params.call("PUT", "/api/TodoItems/{id}").should eq(["id:json", "id:path", "isComplete:json", "name:json"])
    params.call("POST", "/api/TodoItems/{id}/complete").should eq(["id:path", "notify:query"])
    params.call("POST", "/Legacy/Save").should eq(["Id:form", "IsComplete:form", "Name:form"])
  end
end
