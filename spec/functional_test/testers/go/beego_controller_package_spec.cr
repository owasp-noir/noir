require "../../func_spec.cr"

# `web.Router(path, &controllers.ApiController{}, "GET:GetUsers")`: the
# mapping names a method of a controller in another package. It is the
# route's handler, and its `Ctx.Input` / `Input().Get` reads are the
# route's params; a method of the same name on another controller type is
# not. `?:owner` is an optional path segment, not a query string.
expected_endpoints = [
  Endpoint.new("/api/get-users", "GET", [
    Param.new("owner", "", "query"),
    Param.new("p", "", "query"),
    Param.new("X-Api-Token", "", "header"),
  ]),
  Endpoint.new("/api/admin/users", "GET", [Param.new("adminOnly", "", "query")]),
  Endpoint.new("/api/notify-payment/:owner/:payment", "POST", [
    Param.new("owner", "", "path"),
    Param.new("payment", "", "path"),
  ]),
  Endpoint.new("/api/notify-payment/:owner", "POST", [Param.new("owner", "", "path")]),
  Endpoint.new("/api/notify-payment", "POST"),
  Endpoint.new("/api/missing", "GET"),
  Endpoint.new("/ping", "GET", [Param.new("echo", "", "query")]),
  Endpoint.new("/users/ping", "GET"),
  Endpoint.new("/users/health", "GET", [Param.new("probe", "", "query")]),
]

tester = FunctionalTester.new("fixtures/go/beego_controller_package/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the routed controller's method as the handler, and nothing for a missing one", tags: "functional" do
  controllers = "./spec/functional_test/fixtures/go/beego_controller_package/controllers/user.go"
  users = tester.app.endpoints.find! { |ep| ep.url == "/api/get-users" }
  users.handler.should eq(Handler.new("ApiController.GetUsers", controllers, 13))
  users.params.map(&.name).should_not contain("adminOnly")
  admin = tester.app.endpoints.find! { |ep| ep.url == "/api/admin/users" }
  admin.handler.should eq(Handler.new("AdminController.GetUsers", controllers, 22))
  admin.params.map(&.name).should_not contain("owner")
  tester.app.endpoints.find! { |ep| ep.url == "/api/missing" }.handler.should be_nil
  tester.app.endpoints.find! { |ep| ep.url == "/ping" }.handler.try(&.name).should eq("LocalController.Ping")
  # A wrapped registration reads its controller off the whole call; a
  # method the type does not have is no other type's.
  ping = tester.app.endpoints.find! { |ep| ep.url == "/users/ping" }
  ping.handler.should be_nil
  ping.params.map(&.name).should_not contain("statusOnly")
  health = tester.app.endpoints.find! { |ep| ep.url == "/users/health" }
  health.handler.should eq(Handler.new("BaseController.Health", "./spec/functional_test/fixtures/go/beego_controller_package/controllers/base.go", 10))
end
