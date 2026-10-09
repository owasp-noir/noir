require "../../func_spec.cr"

expected_endpoints = [
  # main.cpp — path-based registerHandler with lambdas
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  # No method list → GET, not the next call's {Post} / {Get, Delete}.
  Endpoint.new("/no-methods", "GET", [
    Param.new("dflt", "", "query"),
  ]),
  Endpoint.new("/named-default", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Path param type annotation stripped: {id:int} → {id}
  Endpoint.new("/items/{id}", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/items/{id}", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/named", "GET", [
    Param.new("q", "", "query"),
  ]),
  # controllers/UsersController.cpp — PATH_LIST_BEGIN with PATH_ADD
  Endpoint.new("/api/users", "GET", [
    Param.new("search", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/users/{id}", "GET"),
  Endpoint.new("/api/users/{id}", "PUT"),
  Endpoint.new("/api/users/{id}", "DELETE"),
  Endpoint.new("/api/users/{id}/profile", "GET", [
    Param.new("X-API-Token", "", "header"),
  ]),
]

tester = FunctionalTester.new("fixtures/cpp/drogon/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Drogon analyzer edge cases", tags: "functional" do
  it "does not leak registerHandler params across sibling lambdas" do
    ping = tester.app.endpoints.find { |e| e.url == "/ping" && e.method == "GET" }
    ping.should_not be_nil
    ping.as(Endpoint).params.any? { |p| p.name == "body" }.should be_false
    ping.as(Endpoint).params.any? { |p| p.name == "Authorization" }.should be_false
  end

  it "does not borrow the next registerHandler's method list or lambda" do
    tester.app.endpoints.select(&.url.in?("/no-methods", "/named-default")).map(&.method).uniq!.should eq(["GET"])
    named = tester.app.endpoints.find! { |e| e.url == "/named-default" }
    named.params.map(&.name).should eq(["q"])
  end
end
