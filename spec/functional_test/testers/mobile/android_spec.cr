require "../../func_spec.cr"

# Mobile entry points keep method = "GET"; the mobile semantics live in
# `protocol`. Endpoint is a struct, so `.tap(&.protocol=)` would NOT persist
# (the block mutates a copy) — build via a Proc that mutates a local and
# returns it, which does persist. FunctionalTester then asserts protocol
# (since it differs from "http") and the linker-extracted callees.
build = ->(url : String, protocol : String, params : Array(Param), callees : Array(String)) do
  ep = Endpoint.new(url, "GET", params)
  ep.protocol = protocol
  callees.each { |name| ep.push_callee(Callee.new(name)) }
  ep
end

no_params = [] of Param

expected_endpoints = [
  # Custom scheme deep link (mobile-scheme), enriched by the code-linkage
  # pass with callees pulled from DeepLinkActivity.onCreate.
  build.call("myapp://complex/:id", "mobile-scheme", [Param.new("id", "", "path")], ["renderProfile", "webView.loadUrl"]),
  build.call("myapp://accounts/profile", "mobile-scheme", no_params, [] of String),
  # Scheme resolved from @string/deep_link_scheme
  build.call("myappstr://settings", "mobile-scheme", no_params, [] of String),
  # Verified App Link over https (universal-link)
  build.call("https://myapp.example.com/complex/:id", "universal-link", [Param.new("id", "", "path")], [] of String),
  # Exported, data-less component (android-intent), synthetic intent:// scheme
  build.call("intent://com.example.myapp/.SyncService", "android-intent", no_params, [] of String),
]

FunctionalTester.new("fixtures/mobile/android/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
