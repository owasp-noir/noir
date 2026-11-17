require "../../func_spec.cr"

# Regression: `com.beust.jcommander.internal.Maps` ships inside the
# JCommander jar, and `@Parameter` is also swagger's. A JAX-RS resource that
# imports the helper, or only JCommander's `JCommander` class next to
# swagger's `Parameter`, must not surface as `cli://WidgetResource` and
# friends. JCommander is in use only when the file imports its API
# (`Parameter`, `Parameters`, `JCommander` or `*`), and `@Parameter` is read
# as a JCommander option only when it resolves to JCommander's.
cli_endpoint = Endpoint.new("cli://Tool", "CLI", [Param.new("verbose", "", "flag")])
cli_endpoint.protocol = "cli"
expected_endpoints = [cli_endpoint]

FunctionalTester.new("fixtures/java/cli_jcommander_gate_fp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("java_cli"),
}).perform_tests
