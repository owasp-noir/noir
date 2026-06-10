require "../../func_spec.cr"

# Mobile entry points keep method = "GET"; the mobile semantics live in
# `protocol`. FunctionalTester checks url / method / protocol / params, so
# the protocol is asserted because it differs from the default "http".
expected_endpoints = [
  # Custom scheme deep links (mobile-scheme)
  Endpoint.new("myapp://complex/:id", "GET", [Param.new("id", "", "path")]).tap(&.protocol = "mobile-scheme"),
  Endpoint.new("myapp://accounts/profile", "GET").tap(&.protocol = "mobile-scheme"),
  # Scheme resolved from @string/deep_link_scheme
  Endpoint.new("myappstr://settings", "GET").tap(&.protocol = "mobile-scheme"),
  # Verified App Link over https (universal-link)
  Endpoint.new("https://myapp.example.com/complex/:id", "GET", [Param.new("id", "", "path")]).tap(&.protocol = "universal-link"),
  # Exported intent components (android-intent), synthetic intent:// scheme
  Endpoint.new("intent://com.example.myapp/.DeepLinkActivity", "GET").tap(&.protocol = "android-intent"),
  Endpoint.new("intent://com.example.myapp/.AccountActivity", "GET").tap(&.protocol = "android-intent"),
  Endpoint.new("intent://com.example.myapp/.SettingsActivity", "GET").tap(&.protocol = "android-intent"),
  Endpoint.new("intent://com.example.myapp/.WebActivity", "GET").tap(&.protocol = "android-intent"),
]

FunctionalTester.new("fixtures/mobile/android/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
