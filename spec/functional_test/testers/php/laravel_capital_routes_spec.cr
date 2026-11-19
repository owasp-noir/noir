require "../../func_spec.cr"

# Route files under a capitalised `Routes/` directory: nwidart modules up to
# v10 (`Modules/Blog/Routes/web.php`, wired by the module's
# RouteServiceProvider through `module_path('Blog', '/Routes/api.php')`) and
# Bagisto packages (`packages/Webkul/Admin/src/Routes/web.php`).
expected_endpoints = [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/blog", "GET"),
  Endpoint.new("/blog/posts", "POST"),
  Endpoint.new("/api/blog", "GET"),
  Endpoint.new("/admin/dashboard", "GET"),
]

FunctionalTester.new("fixtures/php/laravel_capital_routes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
