require "../../func_spec.cr"

# Each project keeps its own App_Start/RouteConfig.cs; neither may overwrite
# the other.
expected_endpoints = [
  Endpoint.new("/routeA/{controller}/{action}/{id}", "GET"),
  Endpoint.new("/routeB/{controller}/{action}/{id}", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_mvc_multi_routeconfig/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET MVC RouteConfig", tags: "functional" do
  it "reports the MapRoute( line of each route" do
    tester.app.endpoints.each do |endpoint|
      line = endpoint.details.code_paths.first.line
      line.should eq(endpoint.url.starts_with?("/routeA") ? 10 : 12)
    end
  end
end
