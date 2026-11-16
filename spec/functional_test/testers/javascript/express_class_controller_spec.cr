require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# Handlers that are methods of a controller instance built in the route file:
# `const users = new UserController()`, then `users.list.bind(users)`, a
# wrapped `asyncHandler(users.create.bind(users))`, or a class field
# (`show = async (req, res) => …`). The method's body is where the route
# reads its input.
expected_endpoints = [
  Endpoint.new("/users", "GET", [Param.new("page", "", "query"), Param.new("pageSize", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/accounts/login", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/accounts/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/javascript/express_class_controller/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

describe "Express handlers on a controller instance", tags: "functional" do
  it "resolves each method inside its own class and leaves an inherited one unclaimed" do
    endpoints = tester.app.endpoints
    handler_of = ->(method : String, url : String) do
      endpoints.find! { |ep| ep.method == method && ep.url == url }.handler.try { |h| {h.name, File.basename(h.path.to_s), h.line} }
    end

    handler_of.call("GET", "/users").should eq({"users.list", "userController.js", 4})
    handler_of.call("POST", "/users").should eq({"users.create", "userController.js", 9})
    handler_of.call("GET", "/users/:id").should eq({"users.show", "userController.js", 14})
    # `login` of AccountController, not the BaseController method above it.
    handler_of.call("POST", "/accounts/login").should eq({"accounts.login", "accountController.js", 14})
    handler_of.call("GET", "/accounts/ping").should be_nil

    endpoints.find! { |ep| ep.method == "GET" && ep.url == "/users" }.callees.map(&.name).should contain("userService.list")

    reached = Noir::CLI::Inspect.reach(endpoints, "controllers/userController.js", nil, false)
    reached.map { |row| "#{row.method} #{row.url}" }.sort!.should eq(["GET /users", "GET /users/:id", "POST /users"])
  end
end
