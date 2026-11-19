require "../../func_spec.cr"

# `basename: "/my-app"` in react-router.config.ts prefixes every route.
FunctionalTester.new("fixtures/javascript/react_router_basename/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/my-app", "GET"),
  Endpoint.new("/my-app/api/users", "GET"),
]).perform_tests
