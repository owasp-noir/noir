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
  # pass with callees + input params read from DeepLinkActivity.onCreate:
  # getQueryParameter -> query, get*Extra -> extra.
  build.call("myapp://complex/:id", "mobile-scheme", [
    Param.new("id", "", "path"),
    Param.new("redirect", "", "query"),
    Param.new("utm_source", "", "query"),
    Param.new("userId", "", "extra"),
    Param.new("verified", "", "extra"),
  ], ["renderProfile", "webView.loadUrl"]),
  # Lifecycle setup before the Intent reads should not consume the bounded
  # callee list; the linker should keep input/delegation calls and extract
  # constant-named extras such as Intent.EXTRA_REFERRER.
  build.call("myapp://router", "mobile-scheme", [
    Param.new("EXTRA_REFERRER", "", "extra"),
    Param.new("EXTRA_TEXT", "", "extra"),
    Param.new("EXTRA_STREAM", "", "extra"),
  ], ["intent.getStringExtra", "getInboundUrl", "handleDeepLink", "prepareInboundUrl", "lookupUrlAndDownload"]),
  build.call("myapp://alias", "mobile-scheme", [
    Param.new("aliasToken", "", "extra"),
  ], ["intent.getStringExtra", "dispatchAlias"]),
  build.call("myapp://accounts/profile", "mobile-scheme", no_params, [] of String),
  # Scheme resolved from @string/deep_link_scheme
  build.call("myappstr://settings", "mobile-scheme", no_params, [] of String),
  # Scheme resolved from a second values file (donottranslate.xml)
  build.call("altscheme://alt", "mobile-scheme", no_params, [] of String),
  # Unresolvable @string scheme: kept verbatim, NOT rooted to /@string/...
  build.call("@string/missing_scheme://ghost", "mobile-scheme", no_params, [] of String),
  # Opaque scheme: `mailto:` has no // authority. (The sibling file/content/
  # `http://*` wildcard-host filter on ShareActivity yields nothing.)
  build.call("mailto:", "mobile-scheme", no_params, [] of String),
  # `market://details` keeps its authority (NOT opaque despite the short list).
  build.call("market://details", "mobile-scheme", no_params, [] of String),
  # Verified App Link over https (universal-link)
  build.call("https://myapp.example.com/complex/:id", "universal-link", [Param.new("id", "", "path")], [] of String),
  # Exported, data-less component (android-intent), synthetic intent:// scheme
  build.call("intent://com.example.myapp/.SyncService", "android-intent", no_params, [] of String),
  # gradle manifestPlaceholders: ${deepLinkScheme} / ${deepLinkHost} resolved
  # from build.gradle defaultConfig (the buildTypes override must not win)
  build.call("myapp://links.example.com", "mobile-scheme", no_params, [] of String),
  # Placeholder missing from build.gradle: kept verbatim (tagged unresolved)
  build.call("myapp://${missingHost}", "mobile-scheme", no_params, [] of String),
  # Jetpack Navigation deep link: {userId} -> :userId path param, ?ref={ref}
  # -> query param; linked to ProfileFragment.onViewCreated for callees.
  build.call("myapp://users/:userId", "mobile-scheme", [
    Param.new("userId", "", "path"),
    Param.new("ref", "", "query"),
  ], ["loadProfile"]),
  # Scheme-less Navigation URI: http/https implied, emitted under https;
  # the trailing `.*` wildcard keeps the literal prefix only.
  build.call("https://nav.example.com/search/", "mobile-scheme", no_params, [] of String),
  # Deep link inside a nested <navigation> graph
  build.call("myapp://settings/notifications", "mobile-scheme", no_params, [] of String),
  # App Link whose scheme and host/path are split across separate <data>
  # elements: Android combines them, so http/https × the two paths all
  # resolve (autoVerify -> universal-link). The scheme-only file/content/
  # https content-handler filter on FileImportActivity produces nothing.
  build.call("http://split.example.com/wiki/", "universal-link", no_params, [] of String),
  build.call("https://split.example.com/wiki/", "universal-link", no_params, [] of String),
  build.call("http://split.example.com/zh", "universal-link", no_params, [] of String),
  build.call("https://split.example.com/zh", "universal-link", no_params, [] of String),
]

FunctionalTester.new("fixtures/mobile/android/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
