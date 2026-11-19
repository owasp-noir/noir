require "../../func_spec.cr"

# `+page@.svelte` is a page; `[[lang]]` serves the URL with and without the
# segment; `[x+2e]` is an escaped `.`.
FunctionalTester.new("fixtures/javascript/sveltekit_conventions/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/checkout", "GET"),
  Endpoint.new("/control", "GET"),
  Endpoint.new("/pricing", "GET"),
  Endpoint.new("/{lang}/pricing", "GET", [Param.new("lang", "", "path")]),
  Endpoint.new("/.well-known/security.txt", "GET"),
]).perform_tests
