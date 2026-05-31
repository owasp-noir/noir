require "../../func_spec.cr"

expected_endpoints = [
  # Basic verbs (lib/MyApp.pm)
  Endpoint.new("/", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path"), Param.new("name", "", "form")]),
  Endpoint.new("/users/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/health", "OPTIONS"),
  Endpoint.new("/profile", "GET", [Param.new("Authorization", "", "header"), Param.new("session_id", "", "cookie")]),
  Endpoint.new("/upload", "POST", [Param.new("document", "", "form")]),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  # any with explicit method list
  Endpoint.new("/feedback", "GET"),
  Endpoint.new("/feedback", "POST"),
  # any bare → every supported verb
  Endpoint.new("/wildcard", "GET"),
  Endpoint.new("/wildcard", "POST"),
  Endpoint.new("/wildcard", "PUT"),
  Endpoint.new("/wildcard", "DELETE"),
  Endpoint.new("/wildcard", "PATCH"),
  Endpoint.new("/wildcard", "OPTIONS"),
  Endpoint.new("/wildcard", "HEAD"),
  # any with single-element method lists (`delete`/`head` spellings) → that
  # verb only, not an expand-to-everything fallback
  Endpoint.new("/cache", "DELETE"),
  Endpoint.new("/heartbeat", "HEAD"),
  # bare any + legacy `param` → query for read verbs, form for write verbs
  Endpoint.new("/notify", "GET", [Param.new("message", "", "query")]),
  Endpoint.new("/notify", "POST", [Param.new("message", "", "form")]),
  Endpoint.new("/notify", "PUT", [Param.new("message", "", "form")]),
  Endpoint.new("/notify", "DELETE", [Param.new("message", "", "form")]),
  Endpoint.new("/notify", "PATCH", [Param.new("message", "", "form")]),
  Endpoint.new("/notify", "OPTIONS", [Param.new("message", "", "query")]),
  Endpoint.new("/notify", "HEAD", [Param.new("message", "", "query")]),
  # wildcard + regex routes
  Endpoint.new("/files/*", "GET"),
  Endpoint.new("/ticket/(?<code>[0-9]+)", "GET", [Param.new("code", "", "path")]),
  # block-scoped prefix (nested)
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/tokens", "POST", [Param.new("scope", "", "form")]),
  Endpoint.new("/api/v2/ping", "GET"),
  # procedural prefix
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/settings", "POST", [Param.new("key", "", "form")]),
  # back to root after `prefix undef`
  Endpoint.new("/ping", "GET"),
]

FunctionalTester.new("fixtures/perl/dancer2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
