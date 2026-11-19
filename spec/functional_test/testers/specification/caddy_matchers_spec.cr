require "../../func_spec.cr"

# Any directive's first argument may be its matcher token, and `@ws path
# /ws /socket/*` is the one-line named matcher. Not matchers: `tls`'s
# certificate paths, a lone `root /srv/www` value, `root` inside
# `file_server`'s own block, and a path under `handle_path`, whose prefix is
# stripped before it is matched.
expected_endpoints = [
  Endpoint.new("/api/*", "ANY"),
  Endpoint.new("/blog/*", "ANY"),
  Endpoint.new("/ws", "ANY"),
  Endpoint.new("/socket/*", "ANY"),
  Endpoint.new("/admin/*", "GET"),
  Endpoint.new("/admin/*", "POST"),
  Endpoint.new("/assets/*", "ANY"),
  Endpoint.new("/app/*", "ANY"),
  Endpoint.new("/app/v2/*", "ANY"),
  Endpoint.new("/strip/*", "ANY"),
]

FunctionalTester.new("fixtures/specification/caddy_matchers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
