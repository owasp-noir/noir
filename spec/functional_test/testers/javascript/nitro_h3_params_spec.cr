require "../../func_spec.cr"

# Destructured `getQuery` / `readBody` reads, the same h3 helpers the Nuxt
# analyzer understands.
expected_endpoints = [
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "body"),
    Param.new("email", "", "body"),
  ]),
]

tester = FunctionalTester.new("fixtures/javascript/nitro_h3_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not take `metadata.source` for a body field", tags: "functional" do
  create = tester.endpoints.find! { |endpoint| endpoint.url == "/api/users" && endpoint.method == "POST" }
  create.params.map(&.name).sort!.should eq(["email", "name"])
end
