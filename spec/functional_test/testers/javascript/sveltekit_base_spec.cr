require "../../func_spec.cr"

# `kit.paths.base` in svelte.config.js prefixes every route; the root page
# is the bare base.
FunctionalTester.new("fixtures/javascript/sveltekit_base/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/greenhouse", "GET"),
  Endpoint.new("/greenhouse/garden", "GET"),
  Endpoint.new("/greenhouse/api/seeds", "GET"),
  Endpoint.new("/greenhouse/plant", "GET"),
  Endpoint.new("/greenhouse/plant", "POST"),
]).perform_tests
