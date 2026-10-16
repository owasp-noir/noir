require "../../func_spec.cr"

# Params read in helpers below the last route belong to the routes that
# reach them (wrapper bodies and 1-hop callees), not to that last route.
# `feedAnimal` reads `c.Param("enclosure")`, which `/keepers/feed` has no
# slot for, and `unused` is reached by no route at all.
expected_endpoints = [
  Endpoint.new("/keepers/list", "GET", [
    Param.new("X-Keeper-Token", "", "header"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/keepers/feed", "POST", [
    Param.new("X-Keeper-Token", "", "header"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/keepers/cages/:cage", "DELETE", [
    Param.new("X-Keeper-Token", "", "header"),
    Param.new("cage", "", "path"),
  ]),
  Endpoint.new("/birds", "GET", [
    Param.new("color", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/echo_helper_params/", {
  :techs => 1,
}, expected_endpoints).perform_tests
