require "../../func_spec.cr"

# A `Deny from all` only counts below the document root it protects.
#
#   * `above/`  -> denied at the app root, above `public/`: it keeps outsiders
#                  out of `src/`, but `public/` is still what is served
#   * `above/public/private/` -> denied below the document root: not reachable
#   * `at/`     -> denied in `public/` itself: not counted, `public/` stays
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [] of Param),
  Endpoint.new("/page.php", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/listing.php", "GET", [
    Param.new("name", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_htaccess_docroot_depth/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "drops what lies outside the document root or is denied below it", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/private/secret.php")
  urls.should_not contain("/above/src/Service.php")
  urls.should_not contain("/src/Service.php")
end
