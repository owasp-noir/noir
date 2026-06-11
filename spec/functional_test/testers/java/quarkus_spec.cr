require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/platform/q/greetings", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/platform/q/greetings/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/platform/q/greetings", "POST", [
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/platform/q/greetings/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("pwd", "", "form"),
  ]),
  Endpoint.new("/platform/q/greetings/upload", "POST", [
    Param.new("image", "", "form"),
  ]),
  Endpoint.new("/platform/q/greetings/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/platform/q/greetings/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/platform/configured-rest/configured", "GET"),
  Endpoint.new("/platform/index.html", "GET"),
  Endpoint.new("/platform/", "GET"),
  Endpoint.new("/platform/assets/app.js", "GET"),
  Endpoint.new("/platform/admin/index.html", "GET"),
  Endpoint.new("/platform/admin/", "GET"),
  Endpoint.new("/platform/reactive/events/:eventId", "GET", [
    Param.new("eventId", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/platform/reactive/commands", "POST", [
    Param.new("payload", "", "json"),
    Param.new("dryRun", "", "query"),
  ]),
  Endpoint.new("/platform/reactive/commands", "PUT", [
    Param.new("payload", "", "json"),
    Param.new("dryRun", "", "query"),
  ]),
  Endpoint.new("/platform/reactive/status", "GET"),
]

FunctionalTester.new("fixtures/java/quarkus/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
