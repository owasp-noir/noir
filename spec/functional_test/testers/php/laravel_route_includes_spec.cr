require "../../func_spec.cr"

# A route file loaded from another route file takes the prefix and
# middleware of the groups around the include, on top of its includer's:
# `Route::prefix('v1')->group(base_path('routes/api/v1.php'))` in
# `routes/api.php`, `require __DIR__.'/admin.php'` inside an `auth` group,
# and a chain `api.php` -> `api/v1.php` -> `api/v1/beta.php`. A top-level
# `require` adds nothing.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/beta/flags", "GET"),
  Endpoint.new("/api/v2/orders", "GET"),
  Endpoint.new("/login", "GET"),
]

tester = FunctionalTester.new("fixtures/php/laravel_route_includes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"ai_context" => YAML::Any.new(true)})
tester.perform_tests

describe "Laravel route file includes", tags: "functional" do
  it "guards an included file by the group around its include" do
    tags = ->(url : String) { tester.app.endpoints.find! { |ep| ep.url == url }.tags.map(&.name) }

    tags.call("/admin/dashboard").should contain("auth")
    tags.call("/api/v2/orders").should contain("auth")
    tags.call("/api/v1/users").should_not contain("auth")
    tags.call("/login").should_not contain("auth")
  end
end
