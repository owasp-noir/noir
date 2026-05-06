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
]

FunctionalTester.new("fixtures/perl/mojolicious/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
