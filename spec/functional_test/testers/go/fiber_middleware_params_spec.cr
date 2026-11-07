require "../../func_spec.cr"

# Shared Fiber middleware reads `c.Params("userId")`. That path param belongs
# only to the route whose URL has the slot. The header and query reads are
# real on every route the middleware runs on.
expected_endpoints = [
  Endpoint.new("/v1/users/", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("redirect", "", "query"),
  ]),
  Endpoint.new("/v1/users/:userId", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("redirect", "", "query"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/v1/auth/send-verification-email", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("redirect", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/go/fiber_middleware_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Fiber middleware path params", tags: "functional" do
  it "does not give a route a path parameter it has no slot for" do
    %w[/v1/users/ /v1/auth/send-verification-email].each do |url|
      endpoint = tester.endpoints.find! { |ep| ep.url == url }
      endpoint.params.select(&.param_type.==("path")).map(&.name).should eq([] of String)
    end
    slotted = tester.endpoints.find! { |ep| ep.url == "/v1/users/:userId" }
    slotted.params.select(&.param_type.==("path")).map(&.name).should eq(["userId"])
  end
end
