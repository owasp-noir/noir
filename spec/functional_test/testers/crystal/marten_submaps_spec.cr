require "../../func_spec.cr"

# Marten splits routing across files: a main `Marten.routes.draw` mounts
# per-app sub-maps (`path "/auth", Auth::ROUTES`) whose own `path`
# declarations live elsewhere. The analyzer must compose the mount prefix
# onto each sub-map route, keep `path ""` mounts (Blog) at the bare path,
# never emit the mount line itself as a junk endpoint, and never emit a
# mounted sub-map's routes a second time un-prefixed.
expected_endpoints = [
  # Blog::ROUTES mounted at "" — bare paths.
  Endpoint.new("/", "GET"),
  Endpoint.new("/posts/<slug:slug>", "GET", [Param.new("slug", "", "path")]),
  # Auth::ROUTES mounted at "/auth" — prefix composed.
  Endpoint.new("/auth/signin", "GET"),
  Endpoint.new("/auth/signup", "GET"),
  # Direct leaf routes on the main map, including one guarded by
  # `if Marten.env.development?`.
  Endpoint.new("/health", "GET"),
  Endpoint.new("/__debug", "GET"),
]

FunctionalTester.new("fixtures/crystal/marten_submaps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
