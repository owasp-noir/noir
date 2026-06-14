require "../../func_spec.cr"

ws_echo = Endpoint.new("/echo", "GET")
ws_echo.protocol = "ws"

ws_socket = Endpoint.new("/api/socket", "GET")
ws_socket.protocol = "ws"

expected_endpoints = [
  # script/myapp.pl (Mojolicious::Lite)
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/protected", "GET", [Param.new("Authorization", "", "header"), Param.new("X-Api-Key", "", "header")]),
  Endpoint.new("/profile", "GET", [Param.new("session_id", "", "cookie"), Param.new("user_preference", "", "cookie")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id/profile", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/health", "OPTIONS"),
  Endpoint.new("/files/*path", "GET", [Param.new("path", "", "path")]),
  ws_echo,
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  # lib/MyApp.pm (full app)
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/login", "POST"),
  Endpoint.new("/api/sync", "GET"),
  Endpoint.new("/api/sync", "POST"),
  ws_socket,
  Endpoint.new("/api/legacy", "GET"),
  # `my $admin = $r->any('/admin')` — the assignment itself defines
  # a catch-all route at `/admin`, AND grouped children at `/admin/...`.
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/admin", "POST"),
  Endpoint.new("/admin", "PUT"),
  Endpoint.new("/admin", "DELETE"),
  Endpoint.new("/admin", "PATCH"),
  Endpoint.new("/admin", "OPTIONS"),
  Endpoint.new("/admin", "HEAD"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users", "POST"),
  Endpoint.new("/admin/users/:id", "GET", [Param.new("id", "", "path")]),
  # Nested `$admin->under('/audit')` builds `/admin/audit/...`.
  Endpoint.new("/admin/audit/logs", "GET"),
  # Inline `$r->under('/v2')->get('/health')` — no named var, prefix
  # comes from the chain.
  Endpoint.new("/v2/health", "GET"),
  # lib/MyApp/Routes.pm — prefix held in a scalar (`my $p = '/tests/<id:num>'`)
  # then consumed by `$r->any($p)`; angle placeholders normalized to `:name`;
  # an empty leaf (`get('')`) resolves to the prefix itself.
  Endpoint.new("/tests/:testid", "GET", [Param.new("testid", "", "path")]),
  Endpoint.new("/tests/:testid/status", "GET", [Param.new("testid", "", "path")]),
  Endpoint.new("/tests/:testid/modules/:name", "GET",
    [Param.new("testid", "", "path"), Param.new("name", "", "path")]),
  # Multi-line `my $api_admin\n  = $api->under('/')->...` keeps the `/api/v1`
  # prefix; relative leaves (`jobs`) join onto it.
  Endpoint.new("/api/v1/jobs", "POST"),
  Endpoint.new("/api/v1/jobs/:jobid", "DELETE", [Param.new("jobid", "", "path")]),
]

FunctionalTester.new("fixtures/perl/mojolicious/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
