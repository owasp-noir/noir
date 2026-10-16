require "../../func_spec.cr"

# Two apps with no `composer.json`, each with a document-root folder holding
# an `index.php` front controller.
#
#   * `legacy/`  -> served from its own root (`index.php`, `admin/`, `api/`)
#                   and also keeps a `public/` folder. The rest of the tree is
#                   still reachable, so `admin/` and `api/` stay.
#   * `managed/` -> `web/` is the one served directory; `src/` and `scripts/`
#                   beside it are code and CLI tooling, not pages.
expected_endpoints = [
  Endpoint.new("/legacy/index.php", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/legacy/admin/index.php", "GET", [] of Param),
  Endpoint.new("/legacy/admin/index.php", "POST", [
    Param.new("user", "", "form"),
  ]),
  Endpoint.new("/legacy/api/ping.php", "GET", [
    Param.new("p", "", "query"),
  ]),
  Endpoint.new("/index.php", "GET", [] of Param),
  Endpoint.new("/home.php", "GET", [
    Param.new("h", "", "query"),
  ]),
  Endpoint.new("/page.php", "GET", [
    Param.new("m", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_legacy_root_with_public/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps the pages beside a public/ folder of a site served from its root", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should contain("/legacy/admin/index.php")
  urls.should contain("/legacy/api/ping.php")
end

it "still drops code and tooling beside a managed document root", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/managed/src/Service.php")
  urls.should_not contain("/managed/scripts/job.php")
end
