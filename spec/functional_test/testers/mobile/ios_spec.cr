require "../../func_spec.cr"

# iOS deep links: Info.plist custom schemes + .entitlements universal links.
# Mobile endpoints keep method = "GET"; the protocol carries the semantics.
# Endpoint is a struct, so `.tap(&.protocol=)` would NOT persist (the block
# mutates a copy) — build via a Proc that returns the mutated local so
# FunctionalTester actually asserts the protocol, callees, and params.
build = ->(url : String, protocol : String, params : Array(Param), callees : Array(String)) do
  ep = Endpoint.new(url, "GET", params)
  ep.protocol = protocol
  callees.each { |name| ep.push_callee(Callee.new(name)) }
  ep
end

no_params = [] of Param

expected_endpoints = [
  # Custom schemes (mobile-scheme), linked to the URL handlers: SceneDelegate
  # `scene(_:openURLContexts:)` callees + the `redirect` query param, plus
  # `routeOpenURL` from the AppDelegate `application(_:open:)` (multi-line
  # signature), and `handleObjcDeepLink` + the `token` query param from the
  # Objective-C `application:openURL:` in LegacyAppDelegate.m.
  build.call("myapp://", "mobile-scheme", [Param.new("redirect", "", "query"), Param.new("token", "", "query")], ["handleDeepLink", "webView?.load", "routeOpenURL", "handleObjcDeepLink"]),
  build.call("myapp-alt://", "mobile-scheme", [Param.new("redirect", "", "query"), Param.new("token", "", "query")], ["handleDeepLink", "webView?.load", "routeOpenURL", "handleObjcDeepLink"]),
  # CFBundleURLSchemes entry `$(BUNDLE_URL_SCHEME)` resolved from Config.xcconfig.
  build.call("resolvedscheme://", "mobile-scheme", no_params, [] of String),
  # CFBundleURLSchemes entry `$(NESTED_BUNDLE_URL_SCHEME)` resolves through
  # another build-setting reference in Config.xcconfig.
  build.call("resolvedscheme-nested://", "mobile-scheme", no_params, [] of String),
  # CFBundleURLSchemes entry `$(PBXPROJ_URL_SCHEME)` resolves from multiple
  # project.pbxproj build configurations.
  build.call("pbxscheme://", "mobile-scheme", no_params, [] of String),
  build.call("pbxscheme-alt://", "mobile-scheme", no_params, [] of String),
  # Universal links (universal-link), linked to the userActivity handlers:
  # the Swift `routeUniversalLink` and the Objective-C `routeObjcUniversalLink`
  # from LegacyAppDelegate.m `application:continueUserActivity:`.
  build.call("https://myapp.example.com/", "universal-link", no_params, ["routeUniversalLink", "routeObjcUniversalLink"]),
  build.call("https://www.example.com/", "universal-link", no_params, ["routeUniversalLink"]),
  # App Clip domain (appclips: in App.entitlements). Same https:// URL
  # mechanism as a universal link, so it shares the protocol and handler
  # linkage. `appclips:myapp.example.com` overlaps the applinks entry above and
  # collapses on the URL, so only this App-Clip-only domain is a new endpoint.
  build.call("https://clip.example.com/", "universal-link", no_params, ["routeUniversalLink"]),
]

FunctionalTester.new("fixtures/mobile/ios/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
