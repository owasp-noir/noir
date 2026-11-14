require "../../func_spec.cr"

# A mounted function that registers nothing itself but returns another
# function's router (#3581): oapi-codegen's `Handler` returns
# `HandlerWithOptions(...)`, and owncast mounts `handlers.New(h).Handler()`,
# a method on the constructor's result that returns `generated.Handler(s)`.
# Both keep their mount prefix and are not also reported unprefixed.
# `Unmounted` delegates the same way but is never mounted, so `/health`
# stays at the root.
expected_endpoints = [
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/v2/emoji", "GET"),
  Endpoint.new("/v2/chat", "GET"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/go/chi_mount_delegation/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
