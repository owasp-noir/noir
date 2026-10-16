require "../../func_spec.cr"

# `user.$userId.stories.tsx` is a flat file route that is served; only the
# Storybook story that builds its own router is skipped.
FunctionalTester.new("fixtures/typescript/tanstack_router_stories_flat_route/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/", "GET", [] of Param),
  Endpoint.new("/user/:userId/stories", "GET", [
    Param.new("userId", "", "path"),
  ]),
]).perform_tests
