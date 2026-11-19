require "../../func_spec.cr"

# `base: '/docs'` in astro.config.mjs prefixes every route; the root page is
# the bare base.
FunctionalTester.new("fixtures/javascript/astro_base/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/docs", "GET"),
  Endpoint.new("/docs/api/search", "GET"),
]).perform_tests
