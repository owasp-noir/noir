require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id/profile", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/protected", "GET", [Param.new("authorization", "", "header")]),
  Endpoint.new("/session", "GET", [Param.new("session_id", "", "cookie")]),
  Endpoint.new("/ping", "HEAD"),
  Endpoint.new("/_/*path", "OPTIONS", [Param.new("path", "", "path")]),
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/webhook", "PUT"),
  Endpoint.new("/api", "GET"), # forward statement
  # ApiRouter endpoints
  Endpoint.new("/status", "GET"),
  Endpoint.new("/items", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/items/:id", "GET", [Param.new("id", "", "path")]),
]

# Bandit always hosts a `Plug.Router`, so the project genuinely uses
# both technologies and both detectors fire. The analyzer-level
# redundancy filter drops `elixir_plug` so endpoints aren't extracted
# twice, but the detection count remains 2.
FunctionalTester.new("fixtures/elixir/bandit/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
