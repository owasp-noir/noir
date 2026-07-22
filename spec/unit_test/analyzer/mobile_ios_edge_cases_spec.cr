require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# Regression coverage for enum-body-parsing edge cases found during code
# review of the initial code-route-harvesting implementation: a naive,
# non-string-aware line scan for brace depth and comments silently dropped
# or corrupted cases in several real Swift shapes. Each case below failed
# under the original implementation. See the memory file
# noir-ios-scheme-harvesting.md for the full incident writeup.
describe "Analyzer::Mobile::Ios (enum-body-parsing edge cases)" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios_code_routes_edge_cases"))

  CodeLocator.instance.clear("ios-info-plist")
  CodeLocator.instance.clear("ios-entitlements")
  CodeLocator.instance.clear("file_map")
  CodeLocator.instance.push("ios-info-plist", File.join(base, "Info.plist"))
  swift_path = File.join(base, "RoutingEdgeCases.swift")
  CodeLocator.instance.register_file(swift_path, File.read(swift_path))

  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "harvests every case of a compact single-line enum" do
    find.call("edgeapp://alpha").not_nil!.protocol.should eq("mobile-scheme")
    find.call("edgeapp://beta").not_nil!.protocol.should eq("mobile-scheme")
    find.call("edgeapp://gamma").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "captures a raw value containing '//' even when the enum's closing brace shares its line" do
    find.call("edgeapp://notes//path").not_nil!.protocol.should eq("mobile-scheme")
    find.call("edgeapp://normal").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "harvests hosts compared via a [...].contains(url.host) array membership check" do
    find.call("edgeapp://digitalcard").not_nil!.protocol.should eq("mobile-scheme")
    find.call("edgeapp://digitaldocs").not_nil!.protocol.should eq("mobile-scheme")
    # Not referenced inside the .contains(...) array, but still part of the
    # enum's real vocabulary once the enum itself is identified as a router.
    find.call("edgeapp://me").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "does not mistake an unrelated enum + unrelated .host on the same line for a routing comparison" do
    find.call("edgeapp://debug").should be_nil
    find.call("edgeapp://info").should be_nil
    find.call("edgeapp://warn").should be_nil
    find.call("edgeapp://error").should be_nil
  end
end
