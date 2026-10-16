require "../../func_spec.cr"

# A document root (`www/`) with no `composer.json` anywhere. Its siblings are
# not served, so CLI tooling (`scripts/`), CI files (`.github/`) and a library
# directory whose `.htaccess` disables PHP (`www/includes/`) must not become
# pages. `.well-known` is the one hidden directory that really is served.
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/page.php", "GET", [] of Param),
  Endpoint.new("/page.php", "POST", [
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/.well-known/webfinger.php", "GET", [
    Param.new("resource", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_docroot_nocomposer/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps tooling, hidden directories and disabled-PHP libraries out", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/scripts/job.php")
  urls.should_not contain("/.github/x.php")
  urls.should_not contain("/.private/secret.php")
  urls.should_not contain("/includes/lib.php")
end
