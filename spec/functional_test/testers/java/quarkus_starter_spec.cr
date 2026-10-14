require "../../func_spec.cr"

# The `code.quarkus.io` starter: the resource imports only `jakarta.ws.rs`
# and Quarkus is named solely by `pom.xml`, which must be enough for both
# the detector and the analyzer's project-root gate.
FunctionalTester.new("fixtures/java/quarkus_starter/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/app/hello", "GET"),
]).perform_tests
