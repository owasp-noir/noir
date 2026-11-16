require "../../func_spec.cr"

# `withRouting(health: '/up', then: ...)`: the health route is one named
# argument, so the `Route::middleware(['web', 'auth'])` group the next
# argument registers guards its own routes file and not `/up`.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/admin/settings", "GET"),
]

tester = FunctionalTester.new("fixtures/php/laravel_health_route/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"ai_context" => YAML::Any.new(true)})
tester.perform_tests

describe "Laravel health route", tags: "functional" do
  it "leaves the health route unguarded and guards the group loaded beside it" do
    tags = ->(url : String) { tester.app.endpoints.find! { |ep| ep.url == url }.tags.map(&.name) }

    tags.call("/up").should_not contain("auth")
    tags.call("/").should_not contain("auth")
    tags.call("/admin/settings").should contain("auth")
  end
end
