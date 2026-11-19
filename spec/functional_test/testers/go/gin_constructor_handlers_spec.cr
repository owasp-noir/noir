require "../../func_spec.cr"

# Method-value handlers on a value a constructor builds (`userHandler :=
# handler.NewUserHandler()`, `h, err := handler.NewOrderHandler()`, a
# same-package `newPinger()`) are typed by the constructor's declared
# result; one held in a struct field (`s.handlers.User.List`, `s.orders.List`)
# by the field's declared type, the struct declared in a sibling file. A
# handler shared by three routes reads `answerid` only where the URL has
# that slot.
expected_endpoints = [
  Endpoint.new("/users", "GET", [Param.new("user_page", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("email", "", "json"), Param.new("role", "", "json")]),
  Endpoint.new("/orders", "GET", [Param.new("order_status", "", "query")]),
  Endpoint.new("/ping", "GET", [Param.new("ping_q", "", "query")]),
  Endpoint.new("/v2/users", "GET", [Param.new("user_page", "", "query")]),
  Endpoint.new("/v2/orders", "GET", [Param.new("order_status", "", "query")]),
  Endpoint.new("/questions/:id", "GET", [Param.new("id", "", "path"), Param.new("share", "", "query")]),
  Endpoint.new("/questions/:id/:title", "GET", [Param.new("id", "", "path"), Param.new("title", "", "path"), Param.new("share", "", "query")]),
  Endpoint.new("/questions/:id/:title/:answerid", "GET", [Param.new("id", "", "path"), Param.new("title", "", "path"), Param.new("answerid", "", "path"), Param.new("share", "", "query")]),
]

tester = FunctionalTester.new("fixtures/go/gin_constructor_handlers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "gin constructor and struct-field handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/gin_constructor_handlers"

  it "binds each route to the method definition, not a guess" do
    find = ->(method : String, url : String) { tester.app.endpoints.find! { |ep| ep.method == method && ep.url == url } }
    find.call("POST", "/users").handler.should eq(Handler.new("userHandler.Create", "#{base}/internal/handler/user.go", 18))
    find.call("GET", "/orders").handler.should eq(Handler.new("orderHandler.List", "#{base}/internal/handler/order.go", 9))
    find.call("GET", "/ping").handler.should eq(Handler.new("health.Ping", "#{base}/main.go", 12))
    find.call("GET", "/v2/users").handler.should eq(Handler.new("s.handlers.User.List", "#{base}/internal/handler/user.go", 14))
    find.call("GET", "/v2/orders").handler.should eq(Handler.new("s.orders.List", "#{base}/internal/handler/order.go", 9))
    tester.app.endpoints.compact_map(&.resolution).should be_empty
  end

  it "attaches a shared handler's path read only where the URL has the slot" do
    expected_endpoints.select(&.url.starts_with?("/questions")).each do |expected|
      actual = tester.app.endpoints.find! { |ep| ep.url == expected.url }
      actual.params.map { |p| {p.name, p.param_type} }.sort!.should eq(expected.params.map { |p| {p.name, p.param_type} }.sort!)
    end
  end
end
