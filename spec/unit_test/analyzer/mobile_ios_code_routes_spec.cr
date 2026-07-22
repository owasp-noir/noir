require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# Code-level deep-link route harvesting: Info.plist only ever declares the
# bare `scheme://`, so real routes (`scheme://host`, full literal URLs) have
# to be recovered from source. Covers the two techniques implemented in
# `Analyzer::Mobile::Ios`:
#   A) `url.host == SomeEnum.someCase.rawValue` -> resolve the enum's full
#      case list, cross only with the app's *primary* scheme family.
#   B) a hardcoded `"scheme://host/path"` string literal.
describe "Analyzer::Mobile::Ios (code-level route harvesting)" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios_code_routes"))

  CodeLocator.instance.clear("ios-info-plist")
  CodeLocator.instance.clear("ios-entitlements")
  CodeLocator.instance.clear("file_map")
  CodeLocator.instance.push("ios-info-plist", File.join(base, "Info.plist"))
  swift_path = File.join(base, "Routing.swift")
  CodeLocator.instance.register_file(swift_path, File.read(swift_path))

  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "still emits the bare schemes from Info.plist" do
    find.call("myapp://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("myappauth://").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "harvests a host from an enum compared via .rawValue against .host" do
    find.call("myapp://settings").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "harvests every case of that enum, not just the one referenced in code" do
    # `profilePage = "profile"` is never compared against `.host` anywhere in
    # the fixture — only `settings` is — but the whole enum's case list is
    # the router's real vocabulary, so it should surface too.
    find.call("myapp://profile").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "does not cross the harvested host with a non-primary scheme" do
    # `myappauth` is a second, separate CFBundleURLTypes entry (an auth
    # callback scheme) — it never shared a routing surface with `myapp` in
    # the plist, so it must not be crossed with `myapp`'s harvested hosts.
    find.call("myappauth://settings").should be_nil
    find.call("myappauth://profile").should be_nil
  end

  it "harvests a hardcoded full deep-link URL literal" do
    find.call("myapp://legacy/debug").not_nil!.protocol.should eq("mobile-scheme")
  end
end
