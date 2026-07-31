require "../../func_spec.cr"

# One solution, two web projects, each declaring its own conventional route
# template. A `MapControllerRoute` in ServiceA's Program.cs says nothing about
# a controller compiled into ServiceB, so neither template may cross over.
#
# Before conventional routes were scoped to the owning `.csproj` directory,
# this fixture produced four endpoints: the cross-product of both templates
# with both controllers (`/a/Beta/Show` and `/b/Alpha/Index` are phantoms).
expected_endpoints = [
  Endpoint.new("/a/Alpha/Index", "GET"),
  Endpoint.new("/b/Beta/Show/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_solution/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC conventional-route project scoping" do
  it "does not apply one project's route template to another project's controller" do
    tester.app.endpoints.any? { |e| e.url == "/a/Beta/Show" }.should be_false
    tester.app.endpoints.any? { |e| e.url == "/b/Alpha/Index" }.should be_false
  end
end
