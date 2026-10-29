require "../../func_spec.cr"

# #3309: `autoRoutes()` (react-router-auto-routes) maps folders to segments
# and `index.tsx` to its folder's URL.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/blog", "GET"),
  Endpoint.new("/blog/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/calls/{season}/{episode}", "GET", [Param.new("season", "", "path"), Param.new("episode", "", "path")]),
  Endpoint.new("/resources/search", "GET"),
]

FunctionalTester.new("fixtures/javascript/react_router_auto_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
