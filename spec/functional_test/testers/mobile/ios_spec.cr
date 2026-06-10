require "../../func_spec.cr"

# iOS deep links: Info.plist custom schemes + .entitlements universal links.
# Mobile endpoints keep method = "GET"; the protocol carries the semantics.
expected_endpoints = [
  # CFBundleURLTypes > CFBundleURLSchemes (mobile-scheme); scheme-only, no path
  Endpoint.new("myapp://", "GET").tap(&.protocol = "mobile-scheme"),
  Endpoint.new("myapp-alt://", "GET").tap(&.protocol = "mobile-scheme"),
  # associated-domains applinks: (universal-link); ?mode= stripped, webcredentials ignored
  Endpoint.new("https://myapp.example.com/", "GET").tap(&.protocol = "universal-link"),
  Endpoint.new("https://www.example.com/", "GET").tap(&.protocol = "universal-link"),
]

FunctionalTester.new("fixtures/mobile/ios/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
