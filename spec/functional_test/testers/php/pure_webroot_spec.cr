require "../../func_spec.cr"

# Regression guard for #2358.
#
# `php_pure` used to emit a pseudo-endpoint for EVERY `.php` file, so a
# framework scan filled up with paths that are not web-reachable
# (`/config/app.php`, `/app/Models/User.php`). The workaround was to drop the
# analyzer entirely whenever a framework was detected — which also lost a
# legacy script sitting inside the document root, the one place it really is
# reachable.
#
# The fixture is the shape that broke: a composer-managed project with a
# `public/` document root, a legacy script inside it, and superglobal-carrying
# files outside it. `src/Internal.php` and `config/app.php` both reference
# `$_GET`/`$_POST` on purpose — carrying params must not be enough to make a
# file an endpoint when it cannot be served.
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/legacy-upload.php", "GET", [
    Param.new("user_id", "", "query"),
  ]),
  Endpoint.new("/legacy-upload.php", "POST", [
    Param.new("doc", "", "file"),
    Param.new("token", "", "form"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_webroot/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not emit files outside the document root" do
  urls = tester.app.endpoints.map(&.url)

  # Both carry superglobals; neither is servable.
  urls.should_not contain("/src/Internal.php")
  urls.should_not contain("/config/app.php")

  # URLs resolve against `public/`, not the scan base.
  urls.should_not contain("/public/index.php")
end
