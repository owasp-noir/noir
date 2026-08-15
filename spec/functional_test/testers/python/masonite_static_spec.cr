require "../../func_spec.cr"

# Masonite maps local directories to URL prefixes via `STATICFILES` in
# `config/filesystem.py` (the default project skeleton ships
# `"storage/static": "static/"`, `"storage/public": "/"`, ...). This
# fixture confirms that mapping is read and the files under each mapped
# directory surface as GET endpoints under the matching URL prefix.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/static/app.css", "GET"),
  Endpoint.new("/robots.txt", "GET"),
]

FunctionalTester.new("fixtures/python/masonite_static/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
