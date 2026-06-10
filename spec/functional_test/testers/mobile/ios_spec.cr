require "../../func_spec.cr"

# iOS deep links: Info.plist custom schemes + .entitlements universal links.
# Mobile endpoints keep method = "GET"; the protocol carries the semantics.
# Endpoint is a struct, so `.tap(&.protocol=)` would NOT persist (the block
# mutates a copy) — build via a Proc that returns the mutated local so
# FunctionalTester actually asserts the protocol.
build = ->(url : String, protocol : String) do
  ep = Endpoint.new(url, "GET")
  ep.protocol = protocol
  ep
end

expected_endpoints = [
  # CFBundleURLTypes > CFBundleURLSchemes (mobile-scheme); scheme-only, no path
  build.call("myapp://", "mobile-scheme"),
  build.call("myapp-alt://", "mobile-scheme"),
  # associated-domains applinks: (universal-link); ?mode= stripped, webcredentials ignored
  build.call("https://myapp.example.com/", "universal-link"),
  build.call("https://www.example.com/", "universal-link"),
]

FunctionalTester.new("fixtures/mobile/ios/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
