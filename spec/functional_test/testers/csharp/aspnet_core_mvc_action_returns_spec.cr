require "../../func_spec.cr"

# Every public instance method of a controller is an action, whatever it
# returns; `[NonAction]`, private, static and framework-hook overrides are not.
expected_endpoints = [
  Endpoint.new("/Documents/Index", "GET"),
  Endpoint.new("/Documents/Download/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Documents/Stream", "GET", [Param.new("path", "", "query")]),
  Endpoint.new("/Documents/Export", "GET", [Param.new("format", "", "query")]),
  Endpoint.new("/Documents/Raw", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/Documents/Robots", "GET"),
  Endpoint.new("/Documents/Go", "GET", [Param.new("url", "", "query")]),
  Endpoint.new("/Documents/Back", "GET", [Param.new("returnUrl", "", "query")]),
  Endpoint.new("/Documents/Health", "GET"),
  Endpoint.new("/Documents/Version", "GET"),
  Endpoint.new("/Documents/Motd", "GET"),
  Endpoint.new("/Documents/Logout", "GET"),
  Endpoint.new("/Documents/Tags", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_action_returns/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
