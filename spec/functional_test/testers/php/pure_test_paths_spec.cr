require "../../func_spec.cr"

# Test, fixture and Orchestra-workbench trees are not part of the served
# application. `docs/`, `lib/docs/` and `examples/` are ordinary directories
# of a plain PHP site and stay (only framework adapters skip a root `docs/`).
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/docs/guides/snippet.php", "GET", [
    Param.new("d", "", "query"),
  ]),
  Endpoint.new("/lib/docs/page.php", "GET", [
    Param.new("p", "", "query"),
  ]),
  Endpoint.new("/examples/demo.php", "GET", [
    Param.new("demo", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_test_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "skips test, fixture and workbench paths", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/workbench/app/Home.php")
  urls.should_not contain("/app/Test/Unit/Helper.php")
  urls.should_not contain("/test/phpunit/Bootstrap.php")
  urls.should_not contain("/legacy_tests/Browser/Case.php")
  urls.should_not contain("/src/Factory/Fixtures/Simple.php")
end
