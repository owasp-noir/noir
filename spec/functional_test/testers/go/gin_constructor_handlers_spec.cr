require "../../func_spec.cr"

# Method-value handlers on a value a constructor builds (`userHandler :=
# handler.NewUserHandler()`, `h, err := handler.NewOrderHandler()`, a
# same-package `newPinger()`) are typed by the constructor's declared
# result; one held in a struct field (`s.handlers.User.List`, `s.orders.List`)
# by the field's declared type, the struct declared in a sibling file.
expected_endpoints = [
  Endpoint.new("/users", "GET", [Param.new("user_page", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("email", "", "json"), Param.new("role", "", "json")]),
  Endpoint.new("/orders", "GET", [Param.new("order_status", "", "query")]),
  Endpoint.new("/ping", "GET", [Param.new("ping_q", "", "query")]),
  Endpoint.new("/v2/users", "GET", [Param.new("user_page", "", "query")]),
  Endpoint.new("/v2/orders", "GET", [Param.new("order_status", "", "query")]),
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
end
