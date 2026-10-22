require "../../func_spec.cr"

# Mix's `deps/` and `_build/` hold Plug/Phoenix's own sources. Their
# `defmacro get` and generator templates must neither shadow the app
# router's verbs nor surface as routes; nor may an in-app macro that merely
# shares a verb's name.
FunctionalTester.new("fixtures/elixir/phoenix_mix_deps/", {
  :techs     => 2,
  :endpoints => 3,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/dev/dashboard", "GET"),
  Endpoint.new("/dev/mailbox", "GET"),
]).perform_tests
