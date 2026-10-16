require "../../func_spec.cr"

# Regression (non-CLI annotation read as a CLI marker): `@Parameter` is also
# swagger/OpenAPI's (JAX-RS resources) and Maven's (Mojos). Only a file that
# names `com.beust.jcommander` may read it as a JCommander option, so the
# resource and the Mojo next to one genuine picocli tool must NOT surface as
# `cli://ItemResource` / `cli://StopMojo`.
cli_endpoint = Endpoint.new("cli://tool", "CLI", [Param.new("verbose", "", "flag")])
cli_endpoint.protocol = "cli"
expected_endpoints = [cli_endpoint]

FunctionalTester.new("fixtures/java/cli_parameter_openapi_fp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("java_cli"),
}).perform_tests
