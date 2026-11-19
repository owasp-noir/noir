require "../../func_spec.cr"

# `$builder->fallbacks()` serves every public action of the scope's
# controllers at `/{controller}/{action}` (dasherized); `index` also at
# `/{controller}`. Callbacks, non-public and `_`-prefixed methods,
# AppController and plugin controllers are not enumerated.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pages/*", "GET"),
  Endpoint.new("/articles", "GET"),
  Endpoint.new("/articles/view", "GET"),
  Endpoint.new("/articles/view-all", "GET"),
  Endpoint.new("/admin/user-groups", "GET"),
]

tester = FunctionalTester.new("fixtures/php/cakephp_fallbacks/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "points a fallback endpoint at its controller action", tags: "functional" do
  endpoint = tester.app.endpoints.find!(&.url.==("/articles/view-all"))
  path_info = endpoint.details.code_paths.first
  path_info.path.should end_with("src/Controller/ArticlesController.php")
  path_info.line.should eq(19)
end
