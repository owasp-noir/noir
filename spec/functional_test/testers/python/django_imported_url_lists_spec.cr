require "../../func_spec.cr"

# pretix's root urlconf: `urlpatterns = common_patterns + ...` names a list
# imported from another urlconf, `include((shop.control.urls, "control"))`
# mounts a module bound by `import shop.control.urls`, and an include()
# concatenates imported lists with an inline one. A list nobody imports
# (`unused_patterns`) is not served.
FunctionalTester.new("fixtures/python/django_imported_url_lists/", {
  :techs     => 1,
  :endpoints => 10,
}, [
  Endpoint.new("/healthcheck/", "GET"),
  Endpoint.new("/api/v1/orders/", "GET"),
  Endpoint.new("/legacy/old/", "GET"),
  Endpoint.new("/one/p/", "GET"),
  Endpoint.new("/two/p/", "GET"),
  # `ev = None`: the include() entry stays, as on a list never followed.
  Endpoint.new("/none/", "GET"),
  Endpoint.new("/control/event/{organizer}/", "GET", [Param.new("organizer", "", "path")]),
  Endpoint.new("/locale/set", "GET"),
  Endpoint.new("/{organizer}/", "GET", [Param.new("organizer", "", "path")]),
  Endpoint.new("/{organizer}/{event}/", "GET", [
    Param.new("event", "", "path"),
    Param.new("organizer", "", "path"),
  ]),
]).perform_tests
