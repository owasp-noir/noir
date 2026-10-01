require "../../func_spec.cr"

# Several `:param`s joined by a literal `-` or `.` inside one segment. The
# hyphen allowed in kebab-case names (`:artifact-id`) used to run through
# the separator, adding a phantom `from-` param beside `from` and `to`.
expected_endpoints = [
  Endpoint.new("/flights/:from-:to", "GET", [
    Param.new("from", "", "path"),
    Param.new("to", "", "path"),
  ]),
  Endpoint.new("/plantae/:genus.:species", "GET", [
    Param.new("genus", "", "path"),
    Param.new("species", "", "path"),
  ]),
  Endpoint.new("/users/:id/files/:identifier", "GET", [
    Param.new("id", "", "path"),
    Param.new("identifier", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/javascript/express_joined_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "declares no param that swallowed a separator", tags: "functional" do
  names = tester.app.endpoints.flat_map(&.params.map(&.name))
  names.select { |name| name.ends_with?('-') || name.ends_with?('.') }.should be_empty
end
