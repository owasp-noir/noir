require "../../func_spec.cr"

# Echo's `g.GET("/:id/card", h.card)` inside `func (h *ContactHandler)
# Register(g *echo.Group)`: the method value is followed into its body, as
# on gin (see `gin_method_value_callees_spec.cr`).
expected_endpoints = [
  Endpoint.new("/contacts/:id/card", "GET", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("os.ReadFile", line: 18))
    ep.push_callee(Callee.new("c.Blob", line: 22))
  end,
  Endpoint.new("/contacts/:id", "DELETE", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("os.Remove", line: 26))
  end,
]

tester = FunctionalTester.new("fixtures/go/echo_method_value_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "does not report the method value itself as a callee", tags: "functional" do
  tester.endpoints.flat_map(&.callees.map(&.name)).should_not contain("h.card")
  tester.endpoints.flat_map(&.callees.map(&.name)).should_not contain("h.remove")
end
