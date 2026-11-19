require "../../func_spec.cr"

# A controller serves the decorated methods of the classes it extends (Nest
# reads route metadata through the prototype chain), same-file or imported,
# unless it redefines the method. The undecorated base class serves nothing
# on its own.
expected_endpoints = [
  Endpoint.new("/users/me", "GET"),
  Endpoint.new("/users/by-uid/:uid", "GET", [Param.new("uid", "", "path")]),
  Endpoint.new("/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("body", "", "body")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/orders", "POST", [Param.new("sku", "", "body")]),
  Endpoint.new("/orders/ping", "GET"),
  Endpoint.new("/invoices/ping", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_inherited_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "NestJS inherited route attribution", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports an inherited route at the subclass that serves it" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/nestjs_inherited_routes/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    list = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/users" }
    list.details.code_paths.first.path.should end_with("src/users/users.controller.ts")
    list.details.code_paths.first.line.should eq(7)
    list.handler.try(&.name).should eq("UsersController.findAll")
  end
end
