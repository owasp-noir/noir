require "../../func_spec.cr"

# `#_` discards the next form at read time and `(comment ...)` blocks never
# run, so routes inside either are not attack surface. Only the live route of
# each framework may come out.
FunctionalTester.new("fixtures/clojure/discard_forms/", {
  :techs     => 3,
  :endpoints => 3,
}, [
  Endpoint.new("/compojure/live", "GET"),
  Endpoint.new("/pedestal/live", "GET"),
  Endpoint.new("/reitit/live", "GET"),
]).perform_tests

FunctionalTester.new("fixtures/clojure/ring_discard/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/ring/live", "GET"),
]).perform_tests
