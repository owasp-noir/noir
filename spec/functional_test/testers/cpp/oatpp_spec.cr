require "../../func_spec.cr"

def oatpp_endpoint(url, method, params = [] of Param)
  Endpoint.new(url, method, params)
end

expected_endpoints = [
  # Sync ENDPOINT with a PATH param (and an ENDPOINT_INFO metadata block that
  # must be ignored).
  oatpp_endpoint("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
  ]),
  # BODY_DTO → json body.
  oatpp_endpoint("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  # QUERY param + HEADER with a name-override 3rd argument.
  oatpp_endpoint("/users/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  # Multiple PATH params.
  oatpp_endpoint("/users/{userId}/posts/{postId}", "DELETE", [
    Param.new("userId", "", "path"),
    Param.new("postId", "", "path"),
  ]),
  # ENDPOINT_ASYNC with a path placeholder.
  oatpp_endpoint("/room/{roomId}", "GET", [
    Param.new("roomId", "", "path"),
  ]),
  # Root async endpoint.
  oatpp_endpoint("/", "GET"),
]

tester = FunctionalTester.new("fixtures/cpp/oatpp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "oat++ ENDPOINT macro edge cases" do
  it "ignores ENDPOINT_INFO metadata macros" do
    # getUserById appears in both ENDPOINT_INFO and ENDPOINT; only one route.
    tester.app.endpoints.count { |e| e.url == "/users/{userId}" && e.method == "GET" }.should eq 1
  end

  it "skips ENDPOINT_ASYNC routes whose path is a runtime expression" do
    tester.app.endpoints.any? { |e| e.url.includes?("statisticsUrl") || e.url.includes?("m_appConfig") }.should be_false
  end
end
