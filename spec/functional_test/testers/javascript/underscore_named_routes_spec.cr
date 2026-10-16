require "../../func_spec.cr"

# snake_case names (`speed_test.js`, `ab_test.js`, `load_test.ts`,
# `ab_test.service.js`) are ordinary production file names. Only a file that
# holds a suite (`describe(` / `Deno.test(`) is a test, whatever it imports.
FunctionalTester.new("fixtures/javascript/express_underscore_names/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/speed", "GET", [] of Param),
  Endpoint.new("/specs", "POST", [] of Param),
]).perform_tests

FunctionalTester.new("fixtures/javascript/fastify_underscore_names/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/ab", "GET", [] of Param),
]).perform_tests

FunctionalTester.new("fixtures/javascript/convex_underscore_names/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/loadtest", "POST", [] of Param),
]).perform_tests

FunctionalTester.new("fixtures/javascript/moleculer_underscore_names/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/ab/variant", "GET", [] of Param),
]).perform_tests
