require "../../func_spec.cr"

# Inline closures that each decode into their own `req`: every closure reads
# the struct its own `req` is declared with, and a resolved decode adds no
# generic `body` marker.
expected_endpoints = [
  Endpoint.new("/login", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/transfer", "POST", [Param.new("from_account", "", "json"), Param.new("to_account", "", "json"), Param.new("amount", "", "json")]),
  Endpoint.new("/comment", "POST", [Param.new("text", "", "json")]),
]

tester = FunctionalTester.new("fixtures/go/http_closure_decode_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "net/http closure decode scope", tags: "functional" do
  it "reads only the closure's own decode target" do
    expected_endpoints.each do |expected|
      actual = tester.app.endpoints.find! { |ep| ep.url == expected.url && ep.method == expected.method }
      actual.params.map { |p| {p.name, p.param_type} }.sort!.should eq(expected.params.map { |p| {p.name, p.param_type} }.sort!)
    end
  end
end
