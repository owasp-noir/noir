require "../../func_spec.cr"

# No document root: the tree itself is served, minus what the app's own
# `.htaccess` files turn away.
#
#   * `include/`  -> `Deny from all`: not reachable
#   * `uploads/`  -> `<Files *.php>` denied: not reachable
#   * `partial/`  -> `Deny from all` but `Allow from 127.0.0.1`: conditional, kept
#   * root        -> denies the single file `config.php`, never the tree
#   * `public/`   -> its `index.php` is a "Silence is golden" stub, so it is
#                    not a front controller and `public/` is no document root
#   * `.github/`  -> hidden directory, never served
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/admin/panel.php", "GET", [] of Param),
  Endpoint.new("/admin/panel.php", "POST", [
    Param.new("user", "", "form"),
  ]),
  Endpoint.new("/partial/status.php", "GET", [
    Param.new("probe", "", "query"),
  ]),
  Endpoint.new("/public/index.php", "GET", [] of Param),
  Endpoint.new("/public/form.php", "GET", [] of Param),
  Endpoint.new("/public/form.php", "POST", [
    Param.new("field", "", "form"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_htaccess_deny/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "drops directories the app's .htaccess denies", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/include/class.mail.php")
  urls.should_not contain("/include/staff/view.inc.php")
  urls.should_not contain("/uploads/shell.php")
  urls.should_not contain("/.github/x.php")
end
