require "../../func_spec.cr"

# A handler that is a method value of the registrar's own receiver
# (`rg.GET("/:id/avatar", h.Avatar)` inside `func (h *UserHandler)
# RegisterRoutes(rg *gin.RouterGroup)`) is followed into the method's body:
# its callees are the body's calls, not the handler reference itself, so
# `query --sink file_io` and `reach` see the file read.
handler_path = "./spec/functional_test/fixtures/go/gin_method_value_callees/handler/user.go"

expected_endpoints = [
  Endpoint.new("/users/:id/avatar", "GET", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("os.ReadFile", handler_path, 21))
    ep.push_callee(Callee.new("c.Data", handler_path, 26))
  end,
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("os.Remove", handler_path, 30))
  end,
]

tester = FunctionalTester.new("fixtures/go/gin_method_value_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "does not report the method value itself as a callee", tags: "functional" do
  tester.endpoints.flat_map(&.callees.map(&.name)).should_not contain("h.Avatar")
  tester.endpoints.flat_map(&.callees.map(&.name)).should_not contain("h.Delete")
end
