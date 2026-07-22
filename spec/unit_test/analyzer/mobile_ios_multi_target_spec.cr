require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# Regression coverage for `best_matching_schemes` in a monorepo scan that
# sees more than one app target's Info.plist at once (KakaoTalk ships ~14).
# A shared, String-backed router enum can be declared once but only ever
# compared against `.host` from *one* target's own source — crossing its
# harvested hosts against every primary scheme in the scan (rather than just
# the target(s) whose Info.plist is nearest to that comparison site) grafts
# one app's whole routing table onto an unrelated app's scheme. This was a
# real bug caught by scanning an actual large monorepo, not by any unit test
# — this fixture pins it down.
#
# `aaa` is deliberately declared primary in *two* Info.plists (AppA, right
# next to the routing code, and the unrelated Vendor/AppC, declared first
# below) — `@primary_scheme_dirs` must keep both directories and score
# against the nearest one. Keeping only the first-seen directory (the bug:
# a plain `||=` instead of an array) would bind `aaa` to Vendor/AppC's far
# directory, tie it with `bbb`, and wrongly let `bbb://foo` through too.
describe "Analyzer::Mobile::Ios (multi-target monorepo scoping)" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios_code_routes_multi"))

  CodeLocator.instance.clear("ios-info-plist")
  CodeLocator.instance.clear("ios-entitlements")
  CodeLocator.instance.clear("file_map")
  CodeLocator.instance.push("ios-info-plist", File.join(base, "Vendor", "AppC", "Info.plist"))
  CodeLocator.instance.push("ios-info-plist", File.join(base, "AppA", "Info.plist"))
  CodeLocator.instance.push("ios-info-plist", File.join(base, "AppB", "Info.plist"))
  swift_path = File.join(base, "AppA", "Routing.swift")
  CodeLocator.instance.register_file(swift_path, File.read(swift_path))

  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "still emits every app's bare scheme" do
    find.call("aaa://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("bbb://").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "crosses a harvested host only with the scheme of the app whose source uses it" do
    # `SharedHost` is only ever compared against `.host` inside AppA's own
    # source — AppB has no such code at all, just a same-named scheme in an
    # unrelated Info.plist elsewhere in the tree.
    find.call("aaa://foo").not_nil!.protocol.should eq("mobile-scheme")
    find.call("bbb://foo").should be_nil
  end

  it "picks the nearest of two Info.plists that both declare the same scheme" do
    # `aaa` is also declared (first) by Vendor/AppC, far from the routing
    # code — the far declaration must not be the only one considered.
    find.call("aaa://foo").not_nil!.protocol.should eq("mobile-scheme")
  end
end
