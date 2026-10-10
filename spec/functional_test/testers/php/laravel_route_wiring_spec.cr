require "../../func_spec.cr"

# A route file's prefix comes from where the app loads it, not from the file.
#   * legacy: RouteServiceProvider — nested chained `->prefix('/admin')->group(base_path(...))`
#     and the older `Route::group(['prefix' => 'api'], function () { require ... })`;
#     a commented-out wiring line must not win.
#   * modern: `bootstrap/app.php` `withRouting(api: ..., apiPrefix: 'api/v2', then: ...)`.
#   * bare: no wiring found, so the skeleton default `/api` applies to routes/api.php.
expected_endpoints = [
  Endpoint.new("/admin/settings", "GET"),
  Endpoint.new("/api/legacy-items", "GET"),
  Endpoint.new("/legacy-home", "GET"),
  Endpoint.new("/api/v2/modern-items", "GET"),
  Endpoint.new("/modern-home", "GET"),
  Endpoint.new("/webhooks/stripe", "POST"),
  Endpoint.new("/api/bare-items", "GET"),
]

FunctionalTester.new("fixtures/php/laravel_route_wiring/", {
  :techs     => 2,
  :endpoints => 7,
}, expected_endpoints).perform_tests
