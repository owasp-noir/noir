require "../../func_spec.cr"

# Groups handed out wrapped in a project type (`type Admin struct {
# fiber.Router }`) and registered on by type (`func RegisterAdmin(admin
# *svr.Admin)`), uber/fx style: the prefix comes from the one group the type
# is built from. `Legacy` is built twice and `Partner` from a group handed
# in, so their routes keep no prefix.
expected_endpoints = [
  Endpoint.new("/api/admin/bonjour", "GET"),
  Endpoint.new("/api/admin/purge", "POST"),
  Endpoint.new("/api/_/health", "GET"),
  Endpoint.new("/api/v2/items", "GET"),
  Endpoint.new("/api/v2/items/:itemId", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/old", "GET"),
  Endpoint.new("/feed", "GET"),
]

FunctionalTester.new("fixtures/go/fiber_typed_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
