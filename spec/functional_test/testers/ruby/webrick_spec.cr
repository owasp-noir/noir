require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "form"),
    Param.new("X-Token", "", "header"),
    Param.new("authorization", "", "header"),
    Param.new("session", "", "cookie"),
    Param.new("preference", "", "cookie"),
    Param.new("layout", "", "cookie"),
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/items", "GET", [
    Param.new("id", "", "query"),
    Param.new("X-Auth", "", "header"),
    Param.new("x-auth", "", "header"),
  ]),
  Endpoint.new("/api/items", "DELETE", [
    Param.new("id", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/ruby/webrick/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "WEBrick cookie name reads", tags: "functional" do
  it "ignores cookie values and unrelated name checks" do
    endpoint = tester.endpoints.find! { |ep| ep.url == "/api/users" && ep.method == "POST" }
    names = endpoint.params.select { |param| param.param_type == "cookie" }.map(&.name)
    names.sort!.should eq(["layout", "preference", "session"])
  end
end
