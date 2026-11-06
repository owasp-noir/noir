require "../../func_spec.cr"

# Route paths built from constants the extractor used to leave as a
# placeholder, inventing a path parameter from a constant's name:
#
#   router.post(`${experienceRoutes.verification}/password`, …)  // Object.freeze({ verification: `${prefix}/verification` })
#   const pathname = `${accountApiPrefix}/tokens`                // accountApiPrefix imported
#
# A placeholder nothing in the scan defines (`${settings.base}`) stays.
FunctionalTester.new("fixtures/javascript/express_object_constants/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/experience/verification/password", "POST"),
  Endpoint.new("/experience/profile/mfa", "POST"),
  Endpoint.new("/my-account/tokens", "GET"),
  Endpoint.new("/my-account/tokens/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/{base}/status", "GET", [Param.new("base", "", "path")]),
]).perform_tests
