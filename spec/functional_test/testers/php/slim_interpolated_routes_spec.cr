require "../../func_spec.cr"

# A pattern that starts with an interpolated prefix is still a route; a
# collection `put("$key", …)` and a config getter beside them are not.
expected_endpoints = [
  Endpoint.new("/{apiPrefix}/users", "GET", [
    Param.new("apiPrefix", "", "path"),
  ]),
  Endpoint.new("/{base}/login", "POST", [
    Param.new("base", "", "path"),
  ]),
  Endpoint.new("/ok", "GET"),
]

tester = FunctionalTester.new("fixtures/php/slim_interpolated_routes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not read a collection put or a config getter as a route", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/{key}")
  urls.should_not contain("/general.timezone")
end
