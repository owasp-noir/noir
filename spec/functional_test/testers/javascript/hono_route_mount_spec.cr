require "../../func_spec.cr"

# Hono mounts a same-file local sub-app via `app.route('/book', book)`. The
# sub-app's routes inherit the `/book` prefix, and the mount call itself
# must NOT leak phantom `/book` routes (the chain scanner used to walk past
# the two-arg `.route(...)` and mis-attribute later verb calls to it).
expected_endpoints = [
  Endpoint.new("/book/list", "GET"),
  Endpoint.new("/book/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/book/", "POST"),
]

FunctionalTester.new("fixtures/javascript/hono_route_mount/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
