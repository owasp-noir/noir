require "../../func_spec.cr"

# Regex routes reach the output without their `^` / `$` / `\Z` anchors and
# with `\.` unescaped. Each analyzer strips them itself, only on routes it
# knows are regexes: Kong's non-regex `/kong-literal$` keeps its `$`.
expected_endpoints = [
  Endpoint.new("/traefik/[0-9]+", "ANY"),
  Endpoint.new("/istio/[0-9]+", "ANY"),
  Endpoint.new("/gateway/[0-9]+", "ANY"),
  Endpoint.new("/kong/[0-9]+", "ANY"),
  Endpoint.new("/kong-literal$", "ANY"),
  Endpoint.new("/ingress/[0-9]+", "GET"),
  Endpoint.new("/tornado/([0-9]+).json", "GET"),
  Endpoint.new("/drogon/([0-9]+)", "GET"),
  Endpoint.new("/httplib/(\\d+)", "GET"),
]

FunctionalTester.new("fixtures/specification/regex_anchors/", {
  :techs     => 8,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
