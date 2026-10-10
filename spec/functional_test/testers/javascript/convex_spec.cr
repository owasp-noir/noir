require "../../func_spec.cr"

# convex/messages.ts holds a route-shaped object but no httpRouter import.
FunctionalTester.new("fixtures/javascript/convex/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/postMessage", "POST"),
  Endpoint.new("/getAuthorMessages/*", "GET"),
  Endpoint.new("/stripe", "POST"),
]).perform_tests
