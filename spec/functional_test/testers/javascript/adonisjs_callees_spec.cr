require "../../func_spec.cr"

root = Endpoint.new("/", "GET")
root.push_callee(Callee.new("HomeController.index"))

create = Endpoint.new("/api/v1/users", "POST")
create.push_callee(Callee.new("UsersController.store"))

resource = Endpoint.new("/articles/:id", "DELETE")
resource.push_callee(Callee.new("ArticlesController.destroy"))

FunctionalTester.new("fixtures/javascript/adonisjs/", {
  :techs     => 1,
  :endpoints => 22,
}, [root, create, resource], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
