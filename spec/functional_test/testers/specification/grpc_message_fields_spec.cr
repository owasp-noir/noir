require "../../func_spec.cr"

# `optional` fields belong to the request; a nested message's or enum's body
# does not, while `oneof` members do.
tester = FunctionalTester.new("fixtures/specification/grpc_message_fields/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/acme.users.v1.Users/ListUsers", "POST", [
    Param.new("tenant", "", "json"),
    Param.new("cursor", "", "json"),
    Param.new("page_size", "", "json"),
    Param.new("filter", "", "json"),
    Param.new("team_id", "", "json"),
    Param.new("org_id", "", "json"),
    Param.new("order", "", "json"),
  ]),
])
tester.perform_tests

describe "gRPC message fields", tags: "functional" do
  it "keeps nested message fields out of the parent" do
    tester.app.endpoints.first.params.map(&.name).should eq(%w[tenant cursor page_size filter team_id org_id order])
  end
end
