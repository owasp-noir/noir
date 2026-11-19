require "../../func_spec.cr"

# `register(plugin, { prefix })` with a prefix held in a constant, an
# imported constant, a template or a concatenation: the plugin file's
# routes were reported without the prefix.
FunctionalTester.new("fixtures/javascript/fastify_register_const_prefix/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/literal/literal-leaf", "GET"),
  Endpoint.new("/api/template/template-leaf", "GET"),
  Endpoint.new("/api/concat/concat-leaf", "GET"),
  Endpoint.new("/local/v1/local-leaf", "GET"),
  Endpoint.new("/api/const-leaf", "GET"),
]).perform_tests
