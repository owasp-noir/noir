require "../../func_spec.cr"

# `app.use('/p', a, b)` and `app.use('/p', [a, b])` mount every router of
# the call; only one of them took the prefix, the others stayed at root.
FunctionalTester.new("fixtures/javascript/express_multi_router_use/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/posts", "GET"),
  Endpoint.new("/v2/users", "GET"),
  Endpoint.new("/v2/tags", "GET"),
  Endpoint.new("/same-file/local-a", "GET"),
  Endpoint.new("/same-file/local-b", "GET"),
]).perform_tests
