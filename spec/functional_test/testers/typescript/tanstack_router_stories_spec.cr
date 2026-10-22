require "../../func_spec.cr"

# A Storybook story that builds a route to render a page is not an app route.
FunctionalTester.new("fixtures/typescript/tanstack_router_stories/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/", "GET", [] of Param),
]).perform_tests
